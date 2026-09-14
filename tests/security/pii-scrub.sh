#!/bin/sh
# PII-scrub proof (Ch.2 validation: early data protection + central filtering).
# Sends logs carrying synthetic 8+ digit refs on two legs and proves the
# digit runs never reach storage (replaced with [REDACTED]):
#   A. platform leg: direct OTLP/HTTP to the gateway retail lane (valid token)
#      -> scrubbed authoritatively by the internal collector transform.
#   B. customer leg: plaintext OTLP/HTTP from inside `client-retail-orders`
#      to client-collector-retail-orders:4318 (no auth, as the app does)
#      -> scrubbed EARLY by the customer-side collector, i.e. before the
#      data leaves the customer network (gateway re-scrubs downstream).
# Markers are synthetic (ACC/CARD prefixes + random digit runs), never real PII.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"

get_token() {
  grep -E "^[[:space:]]*(export[[:space:]]+)?$2=" "$1" 2>/dev/null | sed -n '$p' \
    | sed -E "s/^[[:space:]]*(export[[:space:]]+)?$2=//" | tr -d '\r' \
    | sed -E "s/^[\"']//; s/[\"']$//"
}

loki_values() {
  # $1 = substring -> matching log lines in retail-client (last 30m).
  start="$(python3 -c "import datetime; print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=30)).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
  docker exec poc-grafana wget -qO- --header='X-Scope-OrgID: retail-client' \
    "http://loki:3100/loki/api/v1/query_range?query=%7Btenant_id%3D%22retail-client%22%7D+%7C%3D+%22$1%22&limit=10&start=$start" 2>/dev/null \
  | Q="$1" python3 -c "
import json, os, sys
q = os.environ['Q']
vals = [v[1] if isinstance(v, list) else v for s in json.load(sys.stdin)['data']['result'] for v in s.get('values', [])]
print('\n'.join(vals))"
}

assert_scrubbed() {
  # $1 = label, $2 = letter-prefix, $3 = raw digit run
  lines="$(loki_values "$2")"
  [ -n "$lines" ] || { echo "FAIL [$1]: probe never arrived in Loki." >&2; exit 1; }
  echo "$lines" | grep -q '\[REDACTED\]' \
    || { echo "FAIL [$1]: no [REDACTED] in stored lines:" >&2; echo "$lines" >&2; exit 1; }
  echo "$lines" | grep -q "$3" \
    && { echo "FAIL [$1]: raw digit run leaked to storage." >&2; exit 1; }
  echo "ok [$1]: delivered redacted, raw digits absent."
}

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found." >&2; exit 1; }
RETAIL_TOKEN="$(get_token "$ROOT/.env" RETAIL_TOKEN)"
[ -n "${RETAIL_TOKEN:-}" ] || { echo "ERROR: RETAIL_TOKEN missing in $ROOT/.env" >&2; exit 1; }

SUF="$(LC_ALL=C tr -dc 'a-z' </dev/urandom | head -c 6)"
A_PRE="platproberef-$SUF"
A_DIGITS="48291735"
B_PRE="earlyproberef-$SUF"
B_DIGITS="91827364"

echo "== A. platform leg (gateway retail lane, valid token) =="
A_BODY="$A_PRE ref ACC $A_DIGITS total 29.99"
code="$(curl -sk --resolve retail-http-otlp.localhost:443:127.0.0.1 \
  -X POST https://retail-http-otlp.localhost:443/v1/logs \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $RETAIL_TOKEN" \
  -d "{\"resourceLogs\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"pii-probe\"}}]},\"scopeLogs\":[{\"scope\":{\"name\":\"pii\"},\"logRecords\":[{\"body\":{\"stringValue\":\"$A_BODY\"}}]}]}]}" \
  -o /dev/null -w '%{http_code}')"
echo "POST -> HTTP $code"
[ "$code" = "200" ] || { echo "FAIL: platform-leg push rejected." >&2; exit 1; }

echo "== B. customer leg (plaintext to local collector from its own network) =="
B_BODY="$B_PRE card $B_DIGITS exp 12-99"
docker exec retail-orders-api wget -qO- --post-data="{\"resourceLogs\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"pii-probe\"}}]},\"scopeLogs\":[{\"scope\":{\"name\":\"pii\"},\"logRecords\":[{\"body\":{\"stringValue\":\"$B_BODY\"}}]}]}]}" \
  --header='Content-Type: application/json' \
  http://client-collector-retail-orders:4318/v1/logs 2>&1 | head -c 200
echo "(empty response body + no error = accepted)"

echo "waiting 25s for batch + export..."
sleep 25

assert_scrubbed "platform-leg" "$A_PRE" "$A_DIGITS"
assert_scrubbed "customer-leg" "$B_PRE" "$B_DIGITS"

echo "PASS: digit runs scrubbed on both legs; storage holds only [REDACTED]."
