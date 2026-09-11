#!/bin/sh
# Start the full POC: observability + banking + insurance.
# Fresh-clone safe: bootstraps missing .env files from .env.example and
# exports the root tokens so all three stacks always agree (FR-06).
# Usage: ./scripts/up.sh [--build] [--no-build]
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OBS="$ROOT/docker-compose.yml"
BANK_DIR="$ROOT/custumers/digital-banking-services"
INS_DIR="$ROOT/custumers/insurance-services"

BUILD="--build"
for arg in "$@"; do
  case "$arg" in
    --no-build) BUILD="" ;;
    --build) BUILD="--build" ;;
    -h|--help)
      echo "Usage: ./scripts/up.sh [--build|--no-build]"
      exit 0 ;;
    *) echo "Unknown flag: $arg (try --help)" >&2; exit 1 ;;
  esac
done

copy_if_missing() {
  if [ ! -f "$2" ]; then
    if [ -f "$1" ]; then
      cp "$1" "$2"
      echo "created $2 from example (edit it for real secrets)"
    else
      echo "WARNING: neither $2 nor $1 exists, continuing with compose defaults" >&2
    fi
  fi
}

# 1. Bootstrap .env files (all gitignored, only *.example is committed).
copy_if_missing "$ROOT/.env.example" "$ROOT/.env"
copy_if_missing "$BANK_DIR/.env.example" "$BANK_DIR/.env"
copy_if_missing "$INS_DIR/.env.example" "$INS_DIR/.env"

# 2. Single source of truth: tokens come from the ROOT .env.
#    Exported shell vars win over each client dir's own .env during
#    `docker compose` interpolation, so gateway and clients cannot drift.
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

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found in PATH." >&2
  exit 1
fi

# host.docker.internal resolves out of the box on Docker Desktop only.
if [ "$(uname -s 2>/dev/null || echo unknown)" = "Linux" ] \
   && [ -z "${OTEL_EXPORTER_OTLP_ENDPOINT:-}" ]; then
  echo "NOTE (Linux/native Docker): host.docker.internal may not resolve."
  echo "If banking/insurance fail to export telemetry, add"
  echo "  extra_hosts: [\"host.docker.internal:host-gateway\"]"
  echo "to the app services (see compose comments) and re-run."
fi

# 3. Start in dependency order: gateway first, clients second.
echo "== observability =="
docker compose -f "$OBS" up -d $BUILD
echo "== banking =="
docker compose -f "$BANK_DIR/docker-compose.yml" up -d $BUILD
echo "== insurance =="
docker compose -f "$INS_DIR/docker-compose.yml" up -d $BUILD

# 4. Wait for the public surface (gateway is distroless: no healthcheck,
#    so poll TCP from the host instead).
wait_tcp() {
  host="$1"; port="$2"; tries="${3:-30}"
  i=1
  while [ "$i" -le "$tries" ]; do
    if python3 -c "import socket,sys; s=socket.create_connection(('$host', $port), timeout=2); s.close()" 2>/dev/null; then
      return 0
    fi
    sleep 2
    i=$((i + 1))
  done
  return 1
}
if command -v python3 >/dev/null 2>&1; then
  for p in 4317 4318 4320 4321 3000; do
    if wait_tcp 127.0.0.1 "$p" 30; then
      echo "ok 127.0.0.1:$p"
    else
      echo "WARNING: 127.0.0.1:$p not reachable yet (see docker compose ps/logs)" >&2
    fi
  done
else
  echo "(python3 not found: skipping TCP wait, giving services 15s to settle)"
  sleep 15
fi

cat <<'EOF'

All stacks started:
  Grafana       http://localhost:3000
  Banking API   http://localhost:8080
  Fraud svc     http://localhost:8081
  Insurance API http://localhost:8083  (container :8080)
  Risk svc      http://localhost:8082
  OTLP banking   4317/gRPC 4318/HTTP | insurance 4320/gRPC 4321/HTTP

Useful:
  ./scripts/down.sh                 # stop everything
  docker compose ps                 # per-stack status (run with -f <compose>)
  docker compose -f docker-compose.yml logs -f otel-gateway
EOF
