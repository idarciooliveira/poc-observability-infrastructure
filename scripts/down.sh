#!/bin/sh
# Stop the full POC (reverse order of up.sh).
# Usage: ./scripts/down.sh [--volumes|-v]   # -v also removes named volumes
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OBS="$ROOT/docker-compose.yml"
BANK_DIR="$ROOT/custumers/digital-banking-services"
INS_DIR="$ROOT/custumers/insurance-services"

DOWN_FLAGS=""
for arg in "$@"; do
  case "$arg" in
    -v|--volumes) DOWN_FLAGS="-v" ;;
    -h|--help)
      echo "Usage: ./scripts/down.sh [--volumes|-v]"
      exit 0 ;;
    *) echo "Unknown flag: $arg (try --help)" >&2; exit 1 ;;
  esac
done

# down only needs interpolation to succeed, not real secrets:
# export root tokens if present, else placeholder so :? fail-closed vars resolve.
get_env_value() {
  key="$2"
  val="$(grep -E "^[[:space:]]*(export[[:space:]]+)?$key=" "$1" 2>/dev/null | sed -n '$p' | sed -E "s/^[[:space:]]*(export[[:space:]]+)?$key=//" | tr -d '\r' | sed -E "s/^[\"']//; s/[\"'][[:space:]]*(#.*)?$//; s/[[:space:]]*(#.*)?$//")"
  printf '%s' "$val"
}
BANKING_TOKEN="$(get_env_value "$ROOT/.env" BANKING_TOKEN)"
INSURANCE_TOKEN="$(get_env_value "$ROOT/.env" INSURANCE_TOKEN)"
GF_ADMIN_USER="$(get_env_value "$ROOT/.env" GF_ADMIN_USER)"
GF_ADMIN_PASSWORD="$(get_env_value "$ROOT/.env" GF_ADMIN_PASSWORD)"
[ -z "${BANKING_TOKEN:-}" ] && BANKING_TOKEN="placeholder-for-down"
[ -z "${INSURANCE_TOKEN:-}" ] && INSURANCE_TOKEN="placeholder-for-down"
[ -z "${GF_ADMIN_USER:-}" ] && GF_ADMIN_USER="placeholder-for-down"
[ -z "${GF_ADMIN_PASSWORD:-}" ] && GF_ADMIN_PASSWORD="placeholder-for-down"
export BANKING_TOKEN INSURANCE_TOKEN GF_ADMIN_USER GF_ADMIN_PASSWORD

# shellcheck disable=SC2086
docker compose -f "$INS_DIR/docker-compose.yml" down $DOWN_FLAGS
# shellcheck disable=SC2086
docker compose -f "$BANK_DIR/docker-compose.yml" down $DOWN_FLAGS
# shellcheck disable=SC2086
docker compose -f "$OBS" down $DOWN_FLAGS

echo "All stacks stopped."
