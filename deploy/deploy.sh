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
# components, so the marker is added to that list.
#
# Env: NAMESPACE, GIT_SHA. Requires helm, jq and a kubeconfig for that namespace.
set -euo pipefail
: "${NAMESPACE:?}" "${GIT_SHA:?}"
source deploy/chart.env

work=$(mktemp -d)
helm pull "$CHART_NAME" --repo "$CHART_REPO" --version "$CHART_VERSION" --untar --untardir "$work"
# The chart ships flagd's config as a file; use this repository's flags instead.
cp src/flagd/demo.flagd.json "$work/$CHART_NAME/flagd/demo.flagd.json"
flags_sha=$(sha256sum src/flagd/demo.flagd.json | cut -c1-16)
schema="$work/$CHART_NAME/values.schema.json"
jq '.definitions.Components.properties["rollout-marker"] = {"$ref": "#/definitions/Component"}' \
    "$schema" > "$schema.new" && mv "$schema.new" "$schema"

extra=()
[ -f deploy/images.branch.yaml ] && extra+=(-f deploy/images.branch.yaml)

# The repository is the source of truth: --force-conflicts takes back fields
# changed by hand (kubectl set env/edit), which server-side apply would refuse.
helm upgrade --install "$RELEASE_NAME" "$work/$CHART_NAME" \
    --namespace "$NAMESPACE" \
    -f deploy/values.yaml -f deploy/values.cio-demo.yaml -f deploy/images.yaml "${extra[@]}" \
    --set-string "components.flagd.podAnnotations.sre-lab/flags-sha=$flags_sha" \
    --set-string "components.rollout-marker.podAnnotations.cio-demo/deploy-sha=${GIT_SHA:0:12}" \
    --server-side=true --force-conflicts \
    --history-max 10 --wait --timeout 15m

kubectl get pods -n "$NAMESPACE" -o wide
