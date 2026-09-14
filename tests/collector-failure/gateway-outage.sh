#!/bin/sh
# Gateway-outage buffering proof (Ch.2 validation, PRD resilience test 1).
# Stops the central gateway while driving retail traffic, restarts it, and
# proves the customer-side collector's file-backed queue recovered everything:
#   Mimir retail_orders_created_total delta == app-level 201 count
# Counters use cumulative temporality, so a full delta match means no
# datapoint was lost in the outage window. Requires: full stack running.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
OBS="$ROOT/docker-compose.yml"
N="${1:-30}"

mimir_counter() {
  docker exec poc-grafana wget -qO- --header='X-Scope-OrgID: retail-client' \
    'http://mimir:9009/prometheus/api/v1/query?query=retail_orders_created_total' 2>/dev/null \
  | python3 -c "import json,sys; r=json.load(sys.stdin)['data']['result']; print(sum(float(s['value'][1]) for s in r))"
}

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found." >&2; exit 1; }
if ! python3 -c "import socket; socket.create_connection(('127.0.0.1', 8084), timeout=5).close()" 2>/dev/null; then
  echo "ERROR: retail-api :8084 not reachable — start the stack first." >&2
  exit 1
fi

BEFORE="$(mimir_counter)"
echo "Mimir retail_orders_created_total before outage: $BEFORE"

echo "== stopping otel-gateway =="
docker compose -f "$OBS" stop otel-gateway >/dev/null
sleep 5

echo "== driving $N orders THROUGH the outage (app must stay 201) =="
OK=0
i=1
while [ "$i" -le "$N" ]; do
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:8084/orders \
    -H 'Content-Type: application/json' -d '{"productId":"PROD-001","quantity":1}')"
  [ "$code" = "201" ] && OK=$((OK + 1))
  i=$((i + 1))
done
echo "app-level 201s during outage: $OK/$N"

echo "== restarting otel-gateway, waiting 60s for file-queue flush =="
docker compose -f "$OBS" start otel-gateway >/dev/null
sleep 60

AFTER="$(mimir_counter)"
echo "Mimir retail_orders_created_total after recovery: $AFTER"
DELTA="$(python3 -c "print(int(float('$AFTER') - float('$BEFORE')))")"
echo "delta=$DELTA app_201s=$OK"

if [ "$OK" -ne "$N" ]; then
  echo "FAIL: app degraded during gateway outage ($OK/$N 201s)." >&2
  exit 1
fi
if [ "$DELTA" -eq "$OK" ]; then
  echo "PASS: file-backed queue buffered and recovered all $OK orders."
else
  echo "FAIL: telemetry loss — delta $DELTA != app 201s $OK." >&2
  exit 1
fi
