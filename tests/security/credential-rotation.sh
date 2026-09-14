#!/bin/sh
# Credential rotation / revocation proof (Ch.2 validation, PRD security 5-6).
# Rotates RETAIL_TOKEN on gateway + client-collector and proves:
#   1. the OLD token is rejected at the edge (HTTP 401 — expired creds dead)
#   2. the NEW token ingests end-to-end (marker lands in retail-client Loki)
# then restores the original token and proves the pipeline is whole again.
# Only RETAIL_TOKEN is touched; banking/insurance lanes are unaffected.
# Portable sh (no `set -e`): every risky step fails via fail(), which
# restores the original tokens and recreates both services first.
set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
OBS="$ROOT/docker-compose.yml"
RETAIL_COMPOSE="$ROOT/custumers/retail-orders-services/docker-compose.yml"
ROOT_ENV="$ROOT/.env"
RETAIL_ENV="$ROOT/custumers/retail-orders-services/.env"

get_token() {
  grep -E "^[[:space:]]*(export[[:space:]]+)?$2=" "$1" 2>/dev/null | sed -n '$p' \
    | sed -E "s/^[[:space:]]*(export[[:space:]]+)?$2=//" | tr -d '\r' \
    | sed -E "s/^[\"']//; s/[\"']$//"
}

set_token() {
  python3 - "$1" "$2" "$3" <<'EOF'
import re, sys
path, key, val = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path).read().split('\n')
pat = re.compile(r'^\s*(export\s+)?' + re.escape(key) + r'=')
out = [(key + '=' + val) if pat.match(ln) else ln for ln in lines]
open(path, 'w').write('\n'.join(out))
EOF
}

post_log() {
  # $1=token $2=marker -> HTTP code
  curl -sk --resolve retail-http-otlp.localhost:443:127.0.0.1 \
    -X POST https://retail-http-otlp.localhost:443/v1/logs \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $1" \
    -d "{\"resourceLogs\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"cred-probe\"}}]},\"scopeLogs\":[{\"scope\":{\"name\":\"cred\"},\"logRecords\":[{\"body\":{\"stringValue\":\"$2\"}}]}]}]}" \
    -o /dev/null -w '%{http_code}'
}

loki_has() {
  start="$(python3 -c "import datetime; print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=30)).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
  docker exec poc-grafana wget -qO- --header='X-Scope-OrgID: retail-client' \
    "http://loki:3100/loki/api/v1/query_range?query=%7Btenant_id%3D%22retail-client%22%7D+%7C%3D+%22$1%22&limit=5&start=$start" 2>/dev/null \
  | HAS="$1" python3 -c "import json,os,sys; d=json.load(sys.stdin); m=os.environ['HAS']; print('YES' if any(m in (v[1] if isinstance(v,list) else v) for s in d['data']['result'] for v in s.get('values',[])) else 'NO')"
}

recreate_platform_leg() {
  docker compose -f "$OBS" up -d otel-gateway >/dev/null 2>&1
  docker compose -f "$RETAIL_COMPOSE" up -d client-collector-retail-orders >/dev/null 2>&1
}

restore() {
  set_token "$ROOT_ENV" RETAIL_TOKEN "$ORIG"
  set_token "$RETAIL_ENV" RETAIL_TOKEN "$ORIG"
  recreate_platform_leg
}

fail() {
  echo "FAIL: $1" >&2
  echo "restoring original token..."
  restore
  sleep 15
  exit 1
}

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found." >&2; exit 1; }

ORIG="$(get_token "$ROOT_ENV" RETAIL_TOKEN)"
[ -n "${ORIG:-}" ] || { echo "ERROR: RETAIL_TOKEN missing in $ROOT_ENV" >&2; exit 1; }
SUF="$(LC_ALL=C tr -dc 'a-z' </dev/urandom | head -c 6)"
NEW="rotated-$SUF"
echo "origin token preserved; rotating to: $NEW"

echo "== baseline: original token ingests (want 200) =="
[ "$(post_log "$ORIG" "cred-base-$SUF")" = "200" ] || fail "baseline push failed"

echo "== rotating gateway + collector to new token =="
set_token "$ROOT_ENV" RETAIL_TOKEN "$NEW"
set_token "$RETAIL_ENV" RETAIL_TOKEN "$NEW"
recreate_platform_leg
READY=""
i=1
while [ "$i" -le 30 ]; do
  [ "$(post_log "$NEW" "cred-ready-$SUF")" = "200" ] && { READY=1; break; }
  sleep 2
  i=$((i + 1))
done
[ -n "$READY" ] || fail "gateway did not come back with rotated token"

echo "== old token rejected (want 401) =="
GOT="$(post_log "$ORIG" "cred-old-$SUF")"
[ "$GOT" = "401" ] || fail "old token not rejected (got HTTP $GOT)"

echo "== new token flows end-to-end =="
[ "$(post_log "$NEW" "cred-new-$SUF")" = "200" ] || fail "new-token push failed"
sleep 25
[ "$(loki_has "cred-new-$SUF")" = "YES" ] || fail "new-token marker missing in retail-client Loki"

echo "== restoring original token =="
restore
sleep 20
[ "$(post_log "$ORIG" "cred-restored-$SUF")" = "200" ] || fail "pipeline not restored (push failed)"
sleep 25
[ "$(loki_has "cred-restored-$SUF")" = "YES" ] || fail "restored marker missing in Loki"

echo "PASS: revoked token 401s, rotated token flows, original restored and healthy."
