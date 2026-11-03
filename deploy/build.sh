#!/usr/bin/env bash
# Builds and pushes every service this branch changed (deploy/changed-services.sh) and
# writes their image references, pinned by digest, to deploy/images.branch.yaml.
#
# Env: REGISTRY (e.g. srelabxyz.azurecr.io), NAMESPACE (= branch, e.g. user3),
#      BASE_REF (default origin/lab), IMAGE_PREFIX (default sre-lab/$NAMESPACE).
#      Requires docker buildx, logged in to REGISTRY.
set -euo pipefail
: "${REGISTRY:?}" "${NAMESPACE:?}"
out=deploy/images.branch.yaml
mapfile -t services < <(deploy/changed-services.sh "${BASE_REF:-origin/lab}")

if [ "${#services[@]}" -eq 0 ]; then
    echo "No service changed relative to the lab baseline — nothing to build."
    echo "components: {}" > "$out"
    exit 0
fi

echo "components:" > "$out"
for svc in "${services[@]}"; do
    repo="$REGISTRY/${IMAGE_PREFIX:-sre-lab/$NAMESPACE}/$svc"
    # Tag = git tree hash of src/<svc>: the same code keeps the same image, so a deploy
    # that changes something else (values, flags, another service) neither rebuilds
    # nor restarts this one.
    tag=$(git rev-parse --short=12 "HEAD:src/$svc")
    if digest=$(docker buildx imagetools inspect "$repo:$tag" --format '{{json .Manifest.Digest}}' 2>/dev/null | tr -d '"') && [ -n "$digest" ]; then
        echo "$svc: $repo:$tag already built ($digest)"
        printf '  %s:\n    imageOverride:\n      repository: %s\n      tag: "%s@%s"\n' \
            "$svc" "$repo" "$tag" "$digest" >> "$out"
        continue
    fi
    echo "::group::build $svc -> $repo:$tag"
    docker buildx bake -f docker-compose.yml "$svc" \
        --set "$svc.tags=$repo:$tag" \
        --set "$svc.platform=linux/amd64" \
        --set "$svc.cache-from=type=registry,ref=$repo:cache" \
        --set "$svc.cache-to=type=registry,ref=$repo:cache,mode=max" \
        --push --metadata-file "/tmp/bake-$svc.json"
    echo "::endgroup::"
    digest=$(jq -r --arg s "$svc" '.[$s]["containerimage.digest"]' "/tmp/bake-$svc.json")
    printf '  %s:\n    imageOverride:\n      repository: %s\n      tag: "%s@%s"\n' \
        "$svc" "$repo" "$tag" "$digest" >> "$out"
    echo "$svc: $repo:$tag@$digest"
done
