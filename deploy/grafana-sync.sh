#!/usr/bin/env bash
# Loads this branch's dashboards and alert rules into its own Grafana folder, which
# then mirrors the repository: what is in observability/ is created or updated,
# dashboards and rule groups that are no longer there are deleted.
#
#   observability/dashboards/*.json   dashboard JSON (Grafana "Export" -> "Export as JSON").
#                                     uid = <namespace>-<file name>; a dashboard variable
#                                     named "namespace" is set to this branch's namespace.
#   observability/alerts/*.yaml       alert rule groups in Grafana's file-provisioning
#                                     format (Alerting -> "Export" -> YAML): groups[].name,
#                                     .interval, .rules[] with uid, title, condition, data,
#                                     for, labels, annotations, noDataState, execErrState.
#                                     Rule uid = <namespace>-<uid>; the folder field is ignored;
#                                     ${NAMESPACE} in the file is replaced with the namespace.
#                                     Grafana 13 needs keepFiringFor/missingSeriesEvalsToResolve,
#                                     defaults 0s and 2 are filled in. Optional
#                                     notification_settings.receiver (a contact point
#                                     name) sends the rule's alerts there directly.
#
# Env: GRAFANA_URL, GRAFANA_TOKEN (service account with Edit on this folder only),
#      GRAFANA_FOLDER_UID, NAMESPACE, GIT_SHA (optional, dashboard version message).
# Requires curl, jq, yq (mikefarah v4).
set -euo pipefail
: "${GRAFANA_URL:?}" "${GRAFANA_TOKEN:?}" "${GRAFANA_FOLDER_UID:?}" "${NAMESPACE:?}"
G="${GRAFANA_URL%/}"
F="$GRAFANA_FOLDER_UID"

api() { # api <method> <path> [json file] -> body on stdout; fails on HTTP >= 400
    local code out
    out=$(mktemp)
    code=$(curl -sS -o "$out" -w '%{http_code}' -X "$1" \
        -H "Authorization: Bearer $GRAFANA_TOKEN" -H 'Content-Type: application/json' \
        "$G$2" ${3:+--data-binary "@$3"})
    if [ "$code" -ge 400 ]; then
        echo "::error::$1 $2 -> HTTP $code: $(head -c 500 "$out")" >&2
        rm -f "$out"
        return 1
    fi
    cat "$out"
    rm -f "$out"
}

uid_for() { # uid_for <name> -> <namespace>-<name>, Grafana's 40-character uid limit
    local u="$NAMESPACE-$1"
    printf '%s' "${u:0:40}"
}

# ── Dashboards ──────────────────────────────────────────────────────────────
declare -A keep_dash=()
shopt -s nullglob
for f in observability/dashboards/*.json; do
    name=$(basename "$f" .json)
    uid=$(uid_for "$name")
    keep_dash[$uid]=1
    body=$(mktemp)
    jq --arg uid "$uid" --arg ns "$NAMESPACE" --arg folder "$F" --arg msg "deploy ${GIT_SHA:-}" '
        (.dashboard // .) as $d
        | {dashboard: ($d
            | .uid = $uid | del(.id) | del(.version)
            | if .templating.list then
                .templating.list |= map(if .name == "namespace"
                  then .query = $ns | .current = {text: $ns, value: $ns}
                       | .options = [{text: $ns, value: $ns, selected: true}]
                  else . end)
              else . end),
           folderUid: $folder, overwrite: true, message: $msg}' "$f" > "$body"
    api POST /api/dashboards/db "$body" >/dev/null
    rm -f "$body"
    echo "dashboard $uid <- $f"
done

existing=$(api GET "/api/search?type=dash-db&folderUIDs=$F&limit=500")
for uid in $(jq -r '.[] | select(.folderUid == "'"$F"'") | .uid' <<<"$existing"); do
    if [ -z "${keep_dash[$uid]:-}" ]; then
        api DELETE "/api/dashboards/uid/$uid" >/dev/null
        echo "dashboard $uid deleted (no longer in observability/dashboards)"
    fi
done

# ── Alert rule groups (ruler API: honours folder permissions) ───────────────
declare -A keep_group=()
for f in observability/alerts/*.yaml observability/alerts/*.yml; do
    # ${NAMESPACE} in a rule file becomes this branch's namespace.
    sed "s/\${NAMESPACE}/$NAMESPACE/g" "$f" | yq -o=json '.groups // []' | jq -c '.[]' | while read -r group; do
        gname=$(jq -r .name <<<"$group")
        body=$(mktemp)
        jq --arg ns "$NAMESPACE" '{
            name: .name,
            interval: (.interval // "1m"),
            rules: [.rules[] | {
              for: (.for // "0s"),
              keep_firing_for: (.keepFiringFor // "0s"),
              labels: ((.labels // {}) + {namespace: $ns}),
              annotations: (.annotations // {}),
              grafana_alert: ({
                uid: (($ns + "-" + .uid)[0:40]),
                title: .title,
                condition: .condition,
                data: .data,
                no_data_state: (.noDataState // "NoData"),
                exec_err_state: (.execErrState // "Error"),
                is_paused: (.isPaused // false),
                missing_series_evals_to_resolve: (.missingSeriesEvalsToResolve // 2)
              } + (if .notification_settings then {notification_settings: .notification_settings} else {} end))
            }]
          }' <<<"$group" > "$body"
        api POST "/api/ruler/grafana/api/v1/rules/$F?subtype=cortex" "$body" >/dev/null
        rm -f "$body"
        echo "rule group $gname <- $f"
    done
    while IFS= read -r g; do keep_group[$g]=1; done < <(yq -r '.groups[].name' "$f")
done

rules=$(api GET "/api/ruler/grafana/api/v1/rules/$F?subtype=cortex" || echo '{}')
while IFS= read -r g; do
    [ -n "$g" ] || continue
    if [ -z "${keep_group[$g]:-}" ]; then
        api DELETE "/api/ruler/grafana/api/v1/rules/$F/$(jq -rn --arg g "$g" '$g|@uri')?subtype=cortex" >/dev/null
        echo "rule group $g deleted (no longer in observability/alerts)"
    fi
done < <(jq -r '[.[]?[]?.name] | unique | .[]' <<<"$rules")
