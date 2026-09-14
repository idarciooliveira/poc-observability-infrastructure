#!/bin/sh
# Tenant-spoof + isolation proof (Ch.2 validation, PRD security tests 1-3).
# Sends a log with a WRONG tenant.id on each lane and proves the gateway
# overwrote it server-side (transform/<tenant> `set`) and storage isolated it
# via X-Scope-OrgID:
#   RETAIL_TOKEN  + tenant.id=banking-client -> retail-client only
#   BANKING_TOKEN + tenant.id=retail-client  -> banking-client only
# Requires: platform stack running (./scripts/up.sh or docker compose up -d),
# root .env with RETAIL_TOKEN/BANKING_TOKEN, 127.0.0.1:443 reachable.
# Markers use letters only: the collector PII scrub redacts digit runs of 8+,
# which would mangle timestamp-based markers (see run history).
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"

get_env_value() {
  key="$2"
  val="$(grep -E "^[[:space:]]*(export[[:space:]]+)?$key=" "$1" 2>/dev/null | sed -n '$p' | sed -E "s/^[[:space:]]*(export[[:space:]]+)?$key=//" | tr -d '\r' | sed -E "s/^[\"']//; s/[\"'][[:space:]]*(#.*)?$//; s/[[:space:]]*(#.*)?$//")"
  printf '%s' "$val"
}

RETAIL_TOKEN="$(get_env_value "$ROOT/.env" RETAIL_TOKEN)"
BANKING_TOKEN="$(get_env_value "$ROOT/.env" BANKING_TOKEN)"
if [ -z "${RETAIL_TOKEN:-}" ] || [ -z "${BANKING_TOKEN:-}" ]; then
  echo "ERROR: RETAIL_TOKEN / BANKING_TOKEN missing in $ROOT/.env" >&2
  exit 1
fi
for cmd in docker curl python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd not found in PATH." >&2; exit 1; }
done
if ! python3 -c "import socket; socket.create_connection(('127.0.0.1', 443), timeout=5).close()" 2>/dev/null; then
  echo "ERROR: 127.0.0.1:443 not reachable — start the platform first." >&2
  exit 1
fi

SUF="$(LC_ALL=C tr -dc 'a-z' </dev/urandom | head -c 6)"
M_RT="spoof-rt-$SUF"
M_BK="spoof-bk-$SUF"
echo "markers: retail=$M_RT banking=$M_BK"

post_log() {
  # $1=host $2=token $3=spoofed-tenant $4=marker $5=probe
  code="$(curl -sk --resolve "$1:443:127.0.0.1" -X POST "https://$1:443/v1/logs" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $2" \
    -d "{\"resourceLogs\":[{\"resource\":{\"attributes\":[{\"key\":\"tenant.id\",\"value\":{\"stringValue\":\"$3\"}},{\"key\":\"service.name\",\"value\":{\"stringValue\":\"spoof-probe\"}}]},\"scopeLogs\":[{\"scope\":{\"name\":\"spoof\"},\"logRecords\":[{\"body\":{\"stringValue\":\"$4\"},\"attributes\":[{\"key\":\"probe\",\"value\":{\"stringValue\":\"$5\"}}]}]}]}]}" \
    -o /dev/null -w '%{http_code}')"
  echo "POST $1 spoof=$3 marker=$4 -> HTTP $code"
  [ "$code" = "200" ] || { echo "ERROR: expected HTTP 200 from $1" >&2; exit 1; }
}

post_log retail-http-otlp.localhost "$RETAIL_TOKEN" banking-client "$M_RT" retail-spoof
post_log banking-http-otlp.localhost "$BANKING_TOKEN" retail-client "$M_BK" banking-spoof

echo "waiting 25s for batch + export..."
sleep 25

START="$(python3 -c "import datetime; print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=30)).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
query_tenant() {
  # $1=tenant $2=marker -> prints YES if marker found in tenant streams
  docker exec poc-grafana wget -qO- --header="X-Scope-OrgID: $1" \
    "http://loki:3100/loki/api/v1/query_range?query=%7Btenant_id%3D%22$1%22%7D&limit=50&start=$START" 2>/dev/null \
  | MARKER="$2" python3 -c "import json,os,sys; d=json.load(sys.stdin); m=os.environ['MARKER']; print('YES' if any(m in (v[1] if isinstance(v,list) else v) for s in d['data']['result'] for v in s.get('values',[])) else 'NO')"
}

RT_IN_RT="$(query_tenant retail-client "$M_RT")"
RT_IN_BK="$(query_tenant banking-client "$M_RT")"
BK_IN_BK="$(query_tenant banking-client "$M_BK")"
BK_IN_RT="$(query_tenant retail-client "$M_BK")"

echo "retail marker in retail-client=$RT_IN_RT (want YES), in banking-client=$RT_IN_BK (want NO)"
echo "banking marker in banking-client=$BK_IN_BK (want YES), in retail-client=$BK_IN_RT (want NO)"

if [ "$RT_IN_RT" = "YES" ] && [ "$RT_IN_BK" = "NO" ] && [ "$BK_IN_BK" = "YES" ] && [ "$BK_IN_RT" = "NO" ]; then
  echo "PASS: gateway overwrote spoofed tenant.id on both lanes; storage isolated."
else
  echo "FAIL: tenant overwrite or isolation broken (see matrix above)." >&2
  exit 1
fi
