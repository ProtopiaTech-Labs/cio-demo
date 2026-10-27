#!/usr/bin/env bash
# Installs the shop into $NAMESPACE: chart from deploy/chart.env, values from
# deploy/values.yaml and deploy/values.cio-demo.yaml, images from deploy/images.yaml
# plus deploy/images.branch.yaml (written by deploy/build.sh), feature flags from
# src/flagd/demo.flagd.json.
#
# Rollout marker: Deployment rollout-marker carries the deployed commit in its pod
# template, so every deploy with a new commit and every `helm rollback` changes that one
# template. Holmes Operator's TriggeredHealthCheck selects only the marker: one check
# per deploy or rollback, however many services it rolls (its cooldown is per
# Deployment and would skip the rollback check). The chart's values schema lists its
# components, so deploy/chart.sh adds the marker to that list.
#
# Env: NAMESPACE, GIT_SHA. Requires helm, jq and a kubeconfig for that namespace.
set -euo pipefail
: "${NAMESPACE:?}" "${GIT_SHA:?}"
# Chart with this repository's flags and the marker in its schema.
source deploy/chart.sh

extra=()
[ -f deploy/images.branch.yaml ] && extra+=(-f deploy/images.branch.yaml)

# The repository is the source of truth: --force-conflicts takes back fields
# changed by hand (kubectl set env/edit), which server-side apply would refuse.
helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
    --namespace "$NAMESPACE" \
    -f deploy/values.yaml -f deploy/values.cio-demo.yaml -f deploy/images.yaml "${extra[@]}" \
    --set-string "components.flagd.podAnnotations.sre-lab/flags-sha=$FLAGS_SHA" \
    --set-string "components.rollout-marker.podAnnotations.cio-demo/deploy-sha=${GIT_SHA:0:12}" \
    --server-side=true --force-conflicts \
    --history-max 10 --wait --timeout 15m

kubectl get pods -n "$NAMESPACE" -o wide
