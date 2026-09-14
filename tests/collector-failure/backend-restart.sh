#!/bin/sh
# Backend-restart recovery proof (Ch.2 validation, PRD resilience test 4).
# Restarts Loki, Tempo and Mimir one by one (internal-collector retry +
# sending_queue must cover each restart), then proves fresh retail telemetry
# lands in Mimir (counter +3) and Loki (probe product visible).
# Requires: full stack running.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
OBS="$ROOT/docker-compose.yml"

mimir_counter() {
  docker exec poc-grafana wget -qO- --header='X-Scope-OrgID: retail-client' \
    'http://mimir:9009/prometheus/api/v1/query?query=retail_orders_created_total' 2>/dev/null \
  | python3 -c "import json,sys; r=json.load(sys.stdin)['data']['result']; print(sum(float(s['value'][1]) for s in r))"
}

loki_has() {
  # $1 = substring -> YES/NO in retail-client streams (last 30m).
  start="$(python3 -c "import datetime; print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=30)).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
  docker exec poc-grafana wget -qO- --header='X-Scope-OrgID: retail-client' \
    "http://loki:3100/loki/api/v1/query_range?query=%7Btenant_id%3D%22retail-client%22%7D+%7C%3D+%22$1%22&limit=5&start=$start" 2>/dev/null \
  | HAS="$1" python3 -c "import json,os,sys; d=json.load(sys.stdin); m=os.environ['HAS']; print('YES' if any(m in (v[1] if isinstance(v,list) else v) for s in d['data']['result'] for v in s.get('values',[])) else 'NO')"
}

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found." >&2; exit 1; }
for p in 8084; do
  python3 -c "import socket; socket.create_connection(('127.0.0.1', $p), timeout=5).close()" 2>/dev/null \
    || { echo "ERROR: retail-api :8084 not reachable." >&2; exit 1; }
done

BEFORE="$(mimir_counter)"
echo "Mimir counter before restarts: $BEFORE"

for svc in loki tempo mimir; do
  echo "== restarting $svc =="
  docker compose -f "$OBS" restart "$svc" >/dev/null
  # Fixed settle + functional check beats image-specific health probes here
  # (loki/mimir are distroless with healthcheck NONE).
  sleep 30
done

echo "== sending 3 probe orders (PROD-002) =="
OK=0
i=1
while [ "$i" -le 3 ]; do
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:8084/orders \
    -H 'Content-Type: application/json' -d '{"productId":"PROD-002","quantity":1}')"
  [ "$code" = "201" ] && OK=$((OK + 1))
  i=$((i + 1))
done
echo "probe 201s: $OK/3"
sleep 45

AFTER="$(mimir_counter)"
DELTA="$(python3 -c "print(int(float('$AFTER') - float('$BEFORE')))")"
LOKI="$(loki_has 'PROD-002')"
echo "mimir delta=$DELTA (want 3) loki_has_probe=$LOKI (want YES)"

if [ "$OK" -ne 3 ]; then
  echo "FAIL: probe traffic failed ($OK/3)." >&2
  exit 1
fi
if [ "$DELTA" -eq 3 ] && [ "$LOKI" = "YES" ]; then
  echo "PASS: all backends restarted independently; fresh telemetry lands in Mimir and Loki."
else
  echo "FAIL: backend recovery incomplete (delta=$DELTA loki=$LOKI)." >&2
  exit 1
fi
