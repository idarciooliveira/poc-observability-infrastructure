#!/bin/sh
# Generate sustained realistic traffic with k6 (grafana/k6 in Docker, no local install).
# Usage: ./scripts/load-k6.sh [--duration-min 5] [--vus 10] [--chaos off|latency|rejects]
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BANK_COMPOSE="$ROOT/custumers/digital-banking-services/docker-compose.yml"
INS_COMPOSE="$ROOT/custumers/insurance-services/docker-compose.yml"
LOAD_DIR="$ROOT/load"

DURATION_MIN=5
VUS=10
CHAOS="off"

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      cat <<'EOF'
Usage: ./scripts/load-k6.sh [--duration-min 5] [--vus 10] [--chaos off|latency|rejects]

  --duration-min  steady-load minutes (default 5; ramp adds +2m, or +1m when <= 2)
  --vus           virtual users per scenario (default 10; banking + insurance run together)
  --chaos         off | latency | rejects (default off)
                  latency: CHAOS_LATENCY_MS=2500 on fraud/risk-service (trips 2s timeout)
                  rejects: CHAOS_REJECT_RATE=0.3 on fraud/risk-service (reject storm)

Examples:
  ./scripts/load-k6.sh --duration-min 1 --vus 2
  ./scripts/load-k6.sh --duration-min 5 --vus 10 --chaos latency

Notes:
  k6 runs in Docker (grafana/k6) on the default bridge network via
  http://host.docker.internal:8080|:8083 (Docker Desktop resolves it;
  native-Linux Engine may need extra_hosts, see compose comments).
EOF
      exit 0 ;;
  esac
done

while [ "$#" -gt 0 ]; do
  case "$1" in
    --duration-min) DURATION_MIN="${2:?missing value}"; shift 2 ;;
    --vus) VUS="${2:?missing value}"; shift 2 ;;
    --chaos) CHAOS="${2:?missing value}"; shift 2 ;;
    *) echo "Unknown flag: $1 (try --help)" >&2; exit 1 ;;
  esac
done

case "$CHAOS" in
  off|latency|rejects) ;;
  *) echo "ERROR: --chaos must be off|latency|rejects (got '$CHAOS')" >&2; exit 1 ;;
esac
if [ "$DURATION_MIN" -lt 1 ]; then echo "ERROR: --duration-min must be >= 1" >&2; exit 1; fi
if [ "$VUS" -lt 1 ]; then echo "ERROR: --vus must be >= 1" >&2; exit 1; fi

# Ramp scales down for short runs so `--duration-min 1` stays a quick smoke test.
RAMP_MIN=2
if [ "$DURATION_MIN" -le 2 ]; then RAMP_MIN=1; fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found in PATH." >&2
  exit 1
fi
if [ ! -f "$LOAD_DIR/poc-load.js" ]; then
  echo "ERROR: load/poc-load.js not found. Run from the repo root." >&2
  exit 1
fi

# Single source of truth (mirrors up.sh): chaos `compose up -d` recreates
# fraud/risk-service, so the root tokens must be exported or compose falls
# back to dir-.env placeholders and the gateway rejects their telemetry.
get_env_value() {
  # $1 = file, $2 = key — handles `KEY=value`, `export KEY=value`, quotes, CR.
  # (uses sed -n '$p' instead of tail: same result, one less dependency)
  key="$2"
  val="$(grep -E "^[[:space:]]*(export[[:space:]]+)?$key=" "$1" 2>/dev/null | sed -n '$p' | sed -E "s/^[[:space:]]*(export[[:space:]]+)?$key=//" | tr -d '\r' | sed -E "s/^[\"']//; s/[\"'][[:space:]]*(#.*)?$//; s/[[:space:]]*(#.*)?$//")"
  printf '%s' "$val"
}
BANKING_TOKEN="$(get_env_value "$ROOT/.env" BANKING_TOKEN)"
INSURANCE_TOKEN="$(get_env_value "$ROOT/.env" INSURANCE_TOKEN)"
if [ -z "${BANKING_TOKEN:-}" ] || [ -z "${INSURANCE_TOKEN:-}" ]; then
  echo "ERROR: BANKING_TOKEN / INSURANCE_TOKEN missing in $ROOT/.env" >&2
  echo "Copy .env.example to .env and set both tokens." >&2
  exit 1
fi
export BANKING_TOKEN INSURANCE_TOKEN

wait_tcp() {
  host="$1"; port="$2"; tries="${3:-5}"
  i=1
  while [ "$i" -le "$tries" ]; do
    if python3 -c "import socket; s=socket.create_connection(('$host', $port), timeout=2); s.close()" 2>/dev/null; then
      return 0
    fi
    sleep 2
    i=$((i + 1))
  done
  return 1
}

set_chaos() {
  # $1 = latency ms, $2 = reject rate. No rebuild needed: fraud/risk-service
  # read CHAOS_* envs on restart.
  echo "== chaos CHAOS_LATENCY_MS=$1 CHAOS_REJECT_RATE=$2 =="
  CHAOS_LATENCY_MS="$1" CHAOS_REJECT_RATE="$2" docker compose -f "$BANK_COMPOSE" up -d fraud-service
  CHAOS_LATENCY_MS="$1" CHAOS_REJECT_RATE="$2" docker compose -f "$INS_COMPOSE" up -d risk-service
}

echo "== banking =="
if wait_tcp 127.0.0.1 8080 5; then
  echo "ok 127.0.0.1:8080 (banking-api)"
else
  echo "WARNING: 127.0.0.1:8080 not reachable — start the stack first: ./scripts/up.sh" >&2
fi
echo "== insurance =="
if wait_tcp 127.0.0.1 8083 5; then
  echo "ok 127.0.0.1:8083 (insurance-api)"
else
  echo "WARNING: 127.0.0.1:8083 not reachable — start the stack first: ./scripts/up.sh" >&2
fi

# Chaos set-up (restored to 0/0 below, even when k6 fails).
if [ "$CHAOS" = "latency" ]; then set_chaos "2500" "0"; fi
if [ "$CHAOS" = "rejects" ]; then set_chaos "0" "0.3"; fi

echo "== k6 (banking + insurance, vus=$VUS steady=${DURATION_MIN}m ramp=${RAMP_MIN}m chaos=$CHAOS) =="
if docker run --rm -i \
  --network bridge \
  -e "BANKING_URL=http://host.docker.internal:8080" \
  -e "INSURANCE_URL=http://host.docker.internal:8083" \
  -e "VUS=$VUS" \
  -e "RAMP_MIN=$RAMP_MIN" \
  -e "STEADY_MIN=$DURATION_MIN" \
  -e "CHAOS_MODE=$CHAOS" \
  -v "$LOAD_DIR:/scripts:ro" \
  grafana/k6 run /scripts/poc-load.js; then
  K6_EXIT=0
else
  K6_EXIT=$?
fi

if [ "$CHAOS" != "off" ]; then
  echo "== chaos restore (0/0) =="
  set_chaos "0" "0"
fi

echo ""
echo "Endpoints: Banking API http://localhost:8080, Insurance API http://localhost:8083,"
echo "  Grafana http://localhost:3000, OTLP banking 4317/4318 | insurance 4320/4321."
exit "$K6_EXIT"
