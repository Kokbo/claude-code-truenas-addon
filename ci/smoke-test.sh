#!/bin/bash
# Smoke test for the image. Usage: ci/smoke-test.sh <image>
set -euo pipefail
IMG="${1:?usage: smoke-test.sh <image>}"
PORT=17681
fail() { echo "FAIL: $*"; docker logs smoke 2>&1 | tail -50 || true; exit 1; }
cleanup() { docker rm -f smoke >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== Binaries"
docker run --rm "$IMG" bash -c 'claude --version && truenas-mcp --version && ttyd --version && tmux -V'

echo "== Refuses to start without a password"
set +e
timeout 60 docker run --rm "$IMG" >/tmp/nopass.log 2>&1
rc=$?
set -e
[ "$rc" = 1 ] || { cat /tmp/nopass.log; fail "expected exit code 1 without TTYD_PASSWORD, got $rc"; }
grep -q "TTYD_PASSWORD is not set" /tmp/nopass.log || fail "missing password error message"

echo "== Starts with a password and a (fake) TrueNAS config"
docker run -d --name smoke -p "$PORT:7681" \
    -e TTYD_PASSWORD=secret -e AUTO_UPDATE_CLAUDE=false \
    -e TRUENAS_URL=localhost -e TRUENAS_API_USER=claude-ro -e TRUENAS_API_KEY=1-fake \
    "$IMG" >/dev/null

for _ in $(seq 1 60); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/" || true)
    [ "$code" = 401 ] && break
    sleep 2
done
[ "${code:-}" = 401 ] || fail "expected 401 without credentials, got ${code:-none}"
code=$(curl -s -o /dev/null -w '%{http_code}' -u claude:secret "http://127.0.0.1:$PORT/")
[ "$code" = 200 ] || fail "expected 200 with credentials, got $code"

docker logs smoke 2>&1 | grep -q "Web terminal on port 7681" || fail "startup did not reach ttyd"
docker logs smoke 2>&1 | grep -q "TrueNAS MCP could not connect" || fail "MCP preflight warning missing"
docker exec smoke jq -e '.mcpServers.truenas.command == "truenas-mcp"' /data/claude.json >/dev/null \
    || fail "truenas MCP server not registered"
docker exec smoke jq -e '.permissions.allow | index("mcp__truenas")' /data/claude/settings.json >/dev/null \
    || fail "read-only tools not pre-approved"
docker exec smoke test -f /data/claude/CLAUDE.md || fail "CLAUDE.md not installed"

echo "== Startup log"
docker logs smoke 2>&1
echo "All smoke tests passed"
