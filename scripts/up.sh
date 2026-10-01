#!/bin/sh
# Start the full POC: observability + banking + insurance + retail-orders.
# Fresh-clone safe: bootstraps missing .env files from .env.example and
# exports the root tokens so all three stacks always agree (FR-06).
# Usage: ./scripts/up.sh [--build] [--no-build]
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OBS="$ROOT/docker-compose.yml"
BANK_DIR="$ROOT/custumers/digital-banking-services"
INS_DIR="$ROOT/custumers/insurance-services"
RETAIL_DIR="$ROOT/custumers/retail-orders-services"

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
copy_if_missing "$RETAIL_DIR/.env.example" "$RETAIL_DIR/.env"

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
RETAIL_TOKEN="$(get_env_value "$ROOT/.env" RETAIL_TOKEN)"
if [ -z "${BANKING_TOKEN:-}" ] || [ -z "${INSURANCE_TOKEN:-}" ] || [ -z "${RETAIL_TOKEN:-}" ]; then
  echo "ERROR: BANKING_TOKEN / INSURANCE_TOKEN / RETAIL_TOKEN missing in $ROOT/.env" >&2
  echo "Copy .env.example to .env and set all three tokens." >&2
  exit 1
fi
export BANKING_TOKEN INSURANCE_TOKEN RETAIL_TOKEN
# Prod hardening #4: Grafana admin comes from the same root .env (fail closed).
GF_ADMIN_USER="$(get_env_value "$ROOT/.env" GF_ADMIN_USER)"
GF_ADMIN_PASSWORD="$(get_env_value "$ROOT/.env" GF_ADMIN_PASSWORD)"
if [ -z "${GF_ADMIN_USER:-}" ] || [ -z "${GF_ADMIN_PASSWORD:-}" ]; then
  echo "ERROR: GF_ADMIN_USER / GF_ADMIN_PASSWORD missing in $ROOT/.env" >&2
  exit 1
fi
export GF_ADMIN_USER GF_ADMIN_PASSWORD

# 2b. Local simulation TLS cert (self-signed *.localhost, committed certs are
# for local simulation only). Regenerate if missing (fresh clone without certs).
CERT_DIR="$ROOT/observability/traefik/certs"
if [ ! -f "$CERT_DIR/edge.crt" ] || [ ! -f "$CERT_DIR/edge.key" ]; then
  echo "== generating local edge TLS cert (*.localhost, simulation only) =="
  mkdir -p "$CERT_DIR"
  openssl req -x509 -newkey rsa:2048 -keyout "$CERT_DIR/edge.key" -out "$CERT_DIR/edge.crt" \
    -days 365 -nodes -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,DNS:*.localhost,DNS:banking-otlp.localhost,DNS:banking-http-otlp.localhost,DNS:insurance-otlp.localhost,DNS:insurance-http-otlp.localhost,DNS:retail-otlp.localhost,DNS:retail-http-otlp.localhost,DNS:grafana.localhost,DNS:traefik"
  cp "$CERT_DIR/edge.crt" "$CERT_DIR/ca.crt"
fi

# 2c. Host DNS: *.localhost must resolve to 127.0.0.1 for browser/k6.
for h in grafana.localhost banking-otlp.localhost insurance-otlp.localhost retail-otlp.localhost; do
  if ! python3 -c "import socket; socket.gethostbyname('$h')" 2>/dev/null; then
    echo "WARNING: $h does not resolve — add '127.0.0.1 $h' to /etc/hosts (or C:\\Windows\\System32\\drivers\\etc\\hosts)" >&2
  fi
done

echo "NOTE: storage isolation is now enforced (Loki/Mimir/Tempo multitenancy)."
echo "If upgrading from a pre-multitenancy stack, run ./scripts/down.sh --volumes once — old data under tenant fake/anonymous is invisible."

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found in PATH." >&2
  exit 1
fi

# 3. Start in dependency order: platform first, clients second.
echo "== observability =="
docker compose -f "$OBS" up -d $BUILD
echo "== banking =="
docker compose -f "$BANK_DIR/docker-compose.yml" up -d $BUILD
echo "== insurance =="
docker compose -f "$INS_DIR/docker-compose.yml" up -d $BUILD
echo "== retail-orders =="
docker compose -f "$RETAIL_DIR/docker-compose.yml" up -d $BUILD

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
  for p in 443 8080 8083 8084; do
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
  Grafana       https://grafana.localhost (Traefik's local certificate may require browser approval)
  Banking API   http://localhost:8080
  Fraud svc     http://localhost:8081
  Insurance API http://localhost:8083  (container :8080)
  Risk svc      http://localhost:8082
  Retail API    http://localhost:8084  (container :8080, via client-collector-retail-orders)
  OTLP edge     https://banking-otlp.localhost and https://insurance-otlp.localhost
                https://retail-otlp.localhost (client collector only)

Useful:
  ./scripts/down.sh                 # stop everything
  docker compose ps                 # per-stack status (run with -f <compose>)
  docker compose -f docker-compose.yml logs -f otel-gateway
EOF
