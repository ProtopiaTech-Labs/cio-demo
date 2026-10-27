#!/usr/bin/env bash
# Checks of workflow CI, runnable locally with the same tools.
#
#   deploy/ci.sh lint <base ref>          linters on the files changed since <base ref>
#   deploy/ci.sh test <service> <base>    build, unit tests and linters of one service
#   deploy/ci.sh config                   Helm chart rendered with deploy/ values and
#                                         validated; feature flags against flagd's schema
#   deploy/ci.sh observability            dashboards and alert rules in observability/
#
# Linters report through reviewdog and only findings on added or changed lines count
# (-filter-mode=added): code inherited from upstream has findings of its own, and a
# one-line fix must not have to clean up the whole file. Errors fail, warnings only
# annotate.
#
# Env: REVIEWDOG_REPORTER  github-pr-annotations in a pull request (with
#                          REVIEWDOG_GITHUB_API_TOKEN), default local (diff against
#                          the merge base with <base ref>)
#      NAMESPACE           for ${NAMESPACE} in alert rules, default cio-demo
# Requires: git, jq, reviewdog; lint: shellcheck, actionlint, yamllint, hadolint, ruff,
# npx, php; test: dotnet (cart), go and golangci-lint (checkout, product-catalog), npm
# (frontend), node (payment); config: helm, kubeconform, check-jsonschema;
# observability: yq (mikefarah v4), promtool.
set -euo pipefail
# The last command of a pipeline (rd) runs in this shell, so fail() sets status here.
shopt -s lastpipe
cmd="${1:?lint|test|config|observability}"
status=0
fail() { status=1; }

# rd <name> <reviewdog args...>: reviewdog on stdin, filtered to the lines this change adds.
rd() {
    local args=(-name="$1" -reporter="${REVIEWDOG_REPORTER:-local}" -filter-mode=added -fail-level=error "${@:2}")
    [ "${REVIEWDOG_REPORTER:-local}" = local ] && args+=(-diff="git diff $MERGE_BASE HEAD")
    reviewdog "${args[@]}" || fail
}

# to_rdjsonl <jq regex>: linter lines -> reviewdog's JSON lines, keeping the severity
# (reviewdog's errorformat parsing drops it, and every warning would fail). Named groups:
# f file, l line, c column, s severity (error/warning/...), m message, code (optional).
to_rdjsonl() {
    jq -Rc --arg re "$1" 'capture($re)? | {
        message: .m, code: {value: (.code // "")},
        location: {path: .f, range: {start: {line: (.l | tonumber), column: ((.c // "1") | tonumber)}}},
        severity: (.s | ascii_downcase | if startswith("e") then "ERROR" elif startswith("w") then "WARNING" else "INFO" end)}'
}

changed() { # changed <regex>: files added or modified since the merge base
    git diff --name-only --diff-filter=AMR "$MERGE_BASE" HEAD | grep -E "$1" || true
}

lint() {
    local files
    mapfile -t files < <(changed '\.sh$')
    if [ "${#files[@]}" -gt 0 ]; then
        { shellcheck -x -f checkstyle "${files[@]}" || true; } | rd shellcheck -f=checkstyle
        # Some syntax errors are only warnings to ShellCheck; bash refuses them.
        local f
        for f in "${files[@]}"; do
            bash -n "$f" 2>"$tmp/sh" || { cat "$tmp/sh"; echo "::error file=$f::bash syntax error"; fail; }
        done
    fi
    mapfile -t files < <(changed '^\.github/workflows/.*\.ya?ml$')
    if [ "${#files[@]}" -gt 0 ]; then
        { actionlint -oneline "${files[@]}" || true; } | rd actionlint -efm='%f:%l:%c: %m' -level=error
    fi
    mapfile -t files < <(changed '\.ya?ml$|^\.yamllint$')
    if [ "${#files[@]}" -gt 0 ]; then
        { yamllint -f parsable "${files[@]}" || true; } |
            to_rdjsonl '^(?<f>[^:]+):(?<l>\d+):(?<c>\d+): \[(?<s>\w+)\] (?<m>.*?)(?: \((?<code>[\w-]+)\))?$' |
            rd yamllint -f=rdjsonl
    fi
    mapfile -t files < <(changed '(^|/)Dockerfile[^/]*$')
    if [ "${#files[@]}" -gt 0 ]; then
        { hadolint -f checkstyle "${files[@]}" || true; } | rd hadolint -f=checkstyle
    fi
    mapfile -t files < <(changed '\.py$')
    if [ "${#files[@]}" -gt 0 ]; then
        # ruff gives no severity: pyflakes (F: undefined names, unused imports) and
        # syntax errors (E9) fail, style findings annotate.
        { ruff check --no-cache --output-format json "${files[@]}" || true; } |
            jq -c '.[] | {message, code: {value: (.code // "")},
                severity: (if (.code // "E9") | test("^(F|E9)") then "ERROR" else "WARNING" end),
                location: {path: .filename, range: {start: {line: .location.row, column: .location.column}}}}' |
            rd ruff -f=rdjsonl
    fi
    mapfile -t files < <(changed '\.md$')
    if [ "${#files[@]}" -gt 0 ]; then
        { npx --yes markdownlint-cli@0.47.0 -c .markdownlint.yaml "${files[@]}" 2>&1 || true; } |
            rd markdownlint -efm='%f:%l:%c %m' -efm='%f:%l %m' -level=error
    fi
    mapfile -t files < <(changed '\.php$')
    local f
    for f in "${files[@]}"; do
        php -l "$f" >/dev/null 2>"$tmp/php" || { cat "$tmp/php"; echo "::error file=$f::PHP syntax error"; fail; }
    done
    mapfile -t files < <(changed '\.json$')
    for f in "${files[@]}"; do
        jq empty "$f" 2>"$tmp/json" || { echo "::error file=$f::not valid JSON: $(cat "$tmp/json")"; fail; }
    done
}

test_service() {
    local svc="${1:?service}" log rc files
    log="$tmp/build.log"
    case "$svc" in
        cart)
            # Analyzer warnings of the changed lines annotate; a compile error fails.
            rc=0
            dotnet build src/cart/tests/cart.tests.csproj -clp:NoSummary -p:GenerateFullPaths=true \
                --nologo -v q >"$log" 2>&1 || rc=$?
            # MSBuild prints each diagnostic once per project that builds the file.
            to_rdjsonl '^(?<f>.+)\((?<l>\d+),(?<c>\d+)\): (?<s>warning|error) (?<code>\w+): (?<m>.*?)(?: \[[^]]*\])?$' <"$log" |
                awk '!seen[$0]++' | rd dotnet -f=rdjsonl
            [ "$rc" -eq 0 ] || { cat "$log"; echo "::error::cart does not build"; fail; return; }
            dotnet test src/cart/tests/cart.tests.csproj --no-build --nologo || fail
            ;;
        checkout|product-catalog)
            # go vet runs inside golangci-lint, filtered to the changed lines: upstream
            # code already fails some of its checks.
            (cd "src/$svc" && go build ./... && go test -vet=off ./...) || fail
            { (cd "src/$svc" && golangci-lint run --path-mode=abs --output.checkstyle.path=stdout \
                --output.text.path=stderr ./...) || true; } | rd golangci-lint -f=checkstyle
            ;;
        frontend)
            (cd src/frontend && npm ci --no-audit --no-fund --ignore-scripts && npx tsc --noEmit) || fail
            mapfile -t files < <(changed '^src/frontend/.*\.(ts|tsx|js|jsx)$' | sed 's|^src/frontend/||')
            if [ "${#files[@]}" -gt 0 ]; then
                { (cd src/frontend && npx eslint -f json "${files[@]}") || true; } |
                    jq -c '.[] | .filePath as $f | .messages[] | {
                        message, code: {value: (.ruleId // "")}, severity: (if .severity == 2 then "ERROR" else "WARNING" end),
                        location: {path: $f, range: {start: {line: (.line // 1), column: (.column // 1)}}}}' |
                    rd eslint -f=rdjsonl
            fi
            ;;
        payment)
            mapfile -t files < <(changed '^src/payment/.*\.js$')
            for f in "${files[@]}"; do node --check "$f" || { echo "::error file=$f::JavaScript syntax error"; fail; }; done
            ;;
        *)
            echo "$svc: no unit tests or linters of its own; the image build compiles it."
            ;;
    esac
}

config() {
    # shellcheck source=deploy/chart.sh
    source deploy/chart.sh
    helm template "$RELEASE_NAME" "$CHART_DIR" --namespace cio-demo \
        -f deploy/values.yaml -f deploy/values.cio-demo.yaml -f deploy/images.yaml \
        --set-string "components.rollout-marker.podAnnotations.cio-demo/deploy-sha=ci" >"$tmp/manifest.yaml" ||
        { echo "::error file=deploy/values.yaml::the chart does not render with deploy/ values"; fail; return; }
    kubeconform -strict -ignore-missing-schemas -summary "$tmp/manifest.yaml" || fail
    check-jsonschema --schemafile https://flagd.dev/schema/v0/flags.json src/flagd/demo.flagd.json || fail
}

observability() {
    # Datasource uids of the cluster's Grafana (kube-prometheus-stack values) and
    # Grafana's own; a rule or panel with another uid loads but never returns data.
    local known='["prometheus","mimir","loki","tempo","pyroscope","__expr__","grafana","-- Grafana --","-- Mixed --","-- Dashboard --"]'
    local ns="${NAMESPACE:-cio-demo}" f json errs="$tmp/errors"
    : >"$errs"
    for f in observability/dashboards/*.json; do
        [ -e "$f" ] || continue
        if ! jq empty "$f" 2>/dev/null; then echo "$f	not valid JSON" >>"$errs"; continue; fi
        jq -r --arg f "$f" --argjson known "$known" '
            (if (.title // "") == "" then "\($f)\tdashboard without title" else empty end),
            ([.. | objects | select(has("gridPos")) | .id | select(. != null)]
              | group_by(.) | map(select(length > 1) | .[0]) | .[] | "\($f)\tpanel id \(.) used twice"),
            ([.. | objects | .datasource? | objects | .uid? | strings | select(startswith("$") | not)]
              | unique | map(select(. as $u | $known | any(. == $u) | not)) | .[]
              | "\($f)\tunknown datasource uid \(.)")' "$f" >>"$errs"
    done

    printf 'groups:\n' >"$tmp/promql.yaml"
    for f in observability/alerts/*.yaml observability/alerts/*.yml; do
        [ -e "$f" ] || continue
        # Same substitution as deploy/grafana-sync.sh.
        if ! json=$(sed "s/\${NAMESPACE}/$ns/g" "$f" | yq -o=json '.' 2>&1); then
            echo "$f	not valid YAML: $json" >>"$errs"; continue
        fi
        jq -r --arg f "$f" --argjson known "$known" '
            def e(m): "\($f)\t\(m)";
            if (.groups | type) != "array" then e("no groups list") else
            .groups[] | . as $g
            | (if (.name // "") == "" then e("group without name") else empty end),
              (if (.interval // "") == "" then e("group \($g.name): no interval") else empty end),
              (.rules // [] | .[] | . as $r | ($r.title // $r.uid // "?") as $t
                | ((["uid", "title", "condition", "data", "for"][] | select(($r[.] // "") == ""))
                     | e("rule \($t): no \(.)")),
                  (if ($r.condition // "") != "" and ([$r.data[]?.refId] | any(. == $r.condition) | not)
                   then e("rule \($t): condition \($r.condition) is not a refId in data") else empty end),
                  ($r.data[]? | select(.datasourceUid as $u | $known | any(. == $u) | not)
                   | e("rule \($t): unknown datasourceUid \(.datasourceUid)")))
            end' <<<"$json" >>"$errs"
        # Rule uids as grafana-sync.sh writes them: namespace prefix, cut to 40 characters.
        jq -r --arg f "$f" --arg ns "$ns" '.groups[]?.rules[]? | select(.uid) | "\(($ns + "-" + .uid)[0:40])\t\($f)"' \
            <<<"$json" >>"$tmp/uids"
        # PromQL of the Prometheus queries, checked by promtool as recording rules.
        jq -r --arg f "$f" '.groups[]?.rules[]? | . as $r | .data[]?
            | select(.datasourceUid == "prometheus" or .datasourceUid == "mimir") | select(.model.expr)
            | {name: "\($f): \($r.title) \(.refId)", rules: [{record: "ci:check", expr: .model.expr}]}
            | tojson' <<<"$json" | while read -r g; do printf '  - %s\n' "$g"; done >>"$tmp/promql.yaml"
    done
    if [ -s "$tmp/uids" ]; then
        cut -f1 "$tmp/uids" | sort | uniq -d | while read -r uid; do
            printf '%s\trule uid %s used twice (after the namespace prefix and the 40-character cut)\n' \
                "$(grep -m1 "^$uid	" "$tmp/uids" | cut -f2)" "$uid"
        done >>"$errs"
    fi
    if grep -q 'ci:check' "$tmp/promql.yaml"; then
        promtool check rules "$tmp/promql.yaml" >"$tmp/promtool" 2>&1 ||
            { cat "$tmp/promtool"; echo "::error file=observability/alerts::PromQL does not parse (above)"; fail; }
    fi
    while IFS=$'\t' read -r file msg; do echo "::error file=$file::$msg"; fail; done <"$errs"
    [ "$status" -ne 0 ] || echo "observability/: dashboards and alert rules are valid."
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
case "$cmd" in
    lint)
        MERGE_BASE=$(git merge-base HEAD "${2:?base ref}")
        lint ;;
    test)
        MERGE_BASE=$(git merge-base HEAD "${3:?base ref}")
        test_service "${2:?service}" ;;
    config) config ;;
    observability) observability ;;
    *) echo "unknown command $cmd" >&2; exit 2 ;;
esac
exit "$status"
