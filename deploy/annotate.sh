#!/usr/bin/env bash
# Marks a deploy or a rollback on the shop's dashboard: a region annotation from the
# start of the workflow run to now on <namespace>-shop-overview. The text is neutral
# (what was deployed, where, by which run), never why: every account that reads the
# dashboard, an AI agent included, sees it. A failed call is a warning, not a failed
# deploy.
#
# Usage: deploy/annotate.sh deploy|rollback [detail]
# Env: GRAFANA_URL, GRAFANA_TOKEN (Edit on the folder: dashboard annotations only),
#      NAMESPACE, RUN_STARTED_MS (epoch ms), GIT_SHA, BASE_REF (deploy: changed services),
#      GITHUB_SERVER_URL, GITHUB_REPOSITORY, GITHUB_RUN_ID.
set -euo pipefail
: "${GRAFANA_URL:?}" "${GRAFANA_TOKEN:?}" "${NAMESPACE:?}" "${RUN_STARTED_MS:?}"
kind="${1:?deploy|rollback}"
detail="${2:-}"
run_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"
sha="${GIT_SHA:0:7}"

tags=("$kind" "$NAMESPACE")
if [ "$kind" = "deploy" ]; then
    mapfile -t services < <(deploy/changed-services.sh "${BASE_REF:-origin/baseline}")
    for s in "${services[@]}"; do tags+=("service:$s"); done
    text="deploy $NAMESPACE $sha, services: ${services[*]:-none} — <a href=\"$run_url\">run</a>"
    tags+=("version:$sha")
else
    text="rollback $NAMESPACE → ${detail:-previous revision} — <a href=\"$run_url\">run</a>"
fi

body=$(jq -cn --arg uid "$NAMESPACE-shop-overview" --argjson t "$RUN_STARTED_MS" \
    --argjson e "$(date +%s%3N)" --arg text "$text" --args '{
      dashboardUID: $uid, time: $t, timeEnd: $e, text: $text, tags: $ARGS.positional}' "${tags[@]}")
code=$(curl -sS -o /tmp/annotation.json -w '%{http_code}' -X POST "${GRAFANA_URL%/}/api/annotations" \
    -H "Authorization: Bearer $GRAFANA_TOKEN" -H 'Content-Type: application/json' -d "$body" || echo 000)
if [ "$code" = "200" ]; then
    echo "annotation $(jq -r .id /tmp/annotation.json): $text"
else
    echo "::warning::Grafana annotation not created (HTTP $code): $(head -c 300 /tmp/annotation.json 2>/dev/null)"
fi
