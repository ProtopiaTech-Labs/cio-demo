#!/usr/bin/env bash
# Prints the services whose src/<service>/ differs between the lab baseline and HEAD.
# Usage: deploy/changed-services.sh [baseline ref, default origin/lab]
set -euo pipefail
ref="${1:-origin/lab}"
# No common history (the baseline was re-published as a new root commit): compare
# with its tip. Without this nothing was built and a deploy silently went back to
# the baseline images.
base=$(git merge-base HEAD "$ref" 2>/dev/null || git rev-parse "$ref")
git diff --name-only "$base" HEAD -- src/ |
    awk -F/ '{print $2}' | sort -u |
    while read -r svc; do
        grep -qx "$svc" deploy/services.txt && echo "$svc"
    done
exit 0
