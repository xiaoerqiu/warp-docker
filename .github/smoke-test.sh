#!/bin/bash
# usage: smoke-test.sh <image> <warp version> <gost version>
set -u

IMAGE=$1
WARP_VERSION=$2
GOST_VERSION=$3
NAME=warp-smoke-test

fail() {
    echo "[smoke-test] FAILED: $1"
    docker logs --tail 50 "$NAME" || true
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    exit 1
}

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" \
    --device-cgroup-rule 'c 10:200 rwm' \
    --cap-add MKNOD --cap-add AUDIT_WRITE --cap-add NET_ADMIN \
    --sysctl net.ipv6.conf.all.disable_ipv6=0 \
    --sysctl net.ipv4.conf.all.src_valid_mark=1 \
    -p 127.0.0.1:1080:1080 \
    "$IMAGE" || fail "container did not start"

docker exec "$NAME" warp-cli --accept-tos --version | grep -qF "$WARP_VERSION" || fail "WARP is not $WARP_VERSION"
docker exec "$NAME" gost -V | grep -qF "$GOST_VERSION" || fail "GOST is not $GOST_VERSION"

TRACE=https://cloudflare.com/cdn-cgi/trace
for proxy in "--socks5-hostname 127.0.0.1:1080" "--proxy http://127.0.0.1:1080"; do
    ok=
    for _ in $(seq 1 24); do
        # shellcheck disable=SC2086
        if curl -fsS -m 10 $proxy "$TRACE" | grep -qE 'warp=(plus|on)'; then
            ok=1
            break
        fi
        sleep 5
    done
    [ -n "$ok" ] || fail "no WARP traffic through $proxy"
    echo "[smoke-test] OK: $proxy"
done

docker rm -f "$NAME" >/dev/null
