#!/bin/sh
# Customer-collector-kill proof (Ch.2 validation, PRD resilience tests 2-3).
# Stops client-collector-retail-orders while driving retail traffic, restarts
# it, and reports the telemetry gap. The app must keep serving 201s (it does
# not depend on the collector); the OTel SDK memory buffer may drop spans/logs
# while the collector is down, so the delta is REPORTED, not asserted —
# counters are cumulative and usually catch up, spans/logs may gap.
# Requires: full stack running.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
RETAIL_COMPOSE="$ROOT/custumers/retail-orders-services/docker-compose.yml"
N="${1:-20}"

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
echo "Mimir retail_orders_created_total before kill: $BEFORE"

echo "== stopping client-collector-retail-orders =="
docker compose -f "$RETAIL_COMPOSE" stop client-collector-retail-orders >/dev/null
sleep 5

echo "== driving $N orders THROUGH the collector outage =="
OK=0
i=1
while [ "$i" -le "$N" ]; do
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:8084/orders \
    -H 'Content-Type: application/json' -d '{"productId":"PROD-001","quantity":1}')"
  [ "$code" = "201" ] && OK=$((OK + 1))
  i=$((i + 1))
done
echo "app-level 201s during outage: $OK/$N"

echo "== restarting collector, waiting 60s for pipeline resume =="
docker compose -f "$RETAIL_COMPOSE" start client-collector-retail-orders >/dev/null
sleep 60

AFTER="$(mimir_counter)"
echo "Mimir retail_orders_created_total after recovery: $AFTER"
python3 -c "b=float('$BEFORE'); a=float('$AFTER'); ok=$OK; print(f'delta={int(a-b)} app_201s={ok} gap={ok-int(a-b)}')"

if [ "$OK" -ne "$N" ]; then
  echo "FAIL: app degraded while its collector was down ($OK/$N 201s)." >&2
  exit 1
fi
echo "PASS: app stayed healthy without its collector; pipeline resumed (see gap above)."
