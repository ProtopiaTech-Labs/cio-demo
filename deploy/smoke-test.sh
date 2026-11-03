#!/usr/bin/env bash
# After a deploy or a rollback: the shop answers through its public address — the home
# page, and the product list from the frontend's API (frontend -> product-catalog).
# helm --wait already waited for Ready pods; this checks the path users take. Retries
# for up to two minutes while the ingress picks up new pods.
#
# Env: SHOP_URL (e.g. https://cio-demo-shop.workshop2.indexoutofrange.com)
set -euo pipefail
: "${SHOP_URL:?}"
url="${SHOP_URL%/}"

check() { # check <path> <jq test of the body, or empty>
    local body code
    body=$(mktemp)
    for _ in $(seq 1 24); do
        code=$(curl -sS -o "$body" -w '%{http_code}' --max-time 10 "$url$1" || echo 000)
        if [ "$code" = 200 ] && { [ -z "$2" ] || jq -e "$2" "$body" >/dev/null 2>&1; }; then
            echo "ok   $1"
            rm -f "$body"
            return 0
        fi
        sleep 5
    done
    echo "::error::$url$1 -> HTTP $code: $(head -c 300 "$body")"
    rm -f "$body"
    return 1
}

rc=0
check / "" || rc=1
check /api/products 'type == "array" and length > 0' || rc=1
exit "$rc"
