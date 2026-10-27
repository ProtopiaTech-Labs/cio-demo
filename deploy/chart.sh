#!/usr/bin/env bash
# Pulls the shop's Helm chart (deploy/chart.env) into a temporary directory and adapts it
# the way every install needs it: flagd's config from this repository, and the rollout
# marker (see deploy/deploy.sh) added to the components the values schema allows.
# Sourced by deploy/deploy.sh and deploy/ci.sh (render without a cluster).
#
# Sets: CHART_DIR (the adapted chart), FLAGS_SHA, and everything in deploy/chart.env.
# Requires helm and jq.
# shellcheck disable=SC2034  # CHART_DIR and FLAGS_SHA are for the script that sources this
source deploy/chart.env

work=$(mktemp -d)
helm pull "$CHART_NAME" --repo "$CHART_REPO" --version "$CHART_VERSION" --untar --untardir "$work"
CHART_DIR="$work/$CHART_NAME"
# The chart ships flagd's config as a file; use this repository's flags instead.
cp src/flagd/demo.flagd.json "$CHART_DIR/flagd/demo.flagd.json"
FLAGS_SHA=$(sha256sum src/flagd/demo.flagd.json | cut -c1-16)
schema="$CHART_DIR/values.schema.json"
jq '.definitions.Components.properties["rollout-marker"] = {"$ref": "#/definitions/Component"}' \
    "$schema" > "$schema.new" && mv "$schema.new" "$schema"
