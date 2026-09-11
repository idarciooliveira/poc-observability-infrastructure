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

# shellcheck disable=SC2086
docker compose -f "$INS_DIR/docker-compose.yml" down $DOWN_FLAGS
# shellcheck disable=SC2086
docker compose -f "$BANK_DIR/docker-compose.yml" down $DOWN_FLAGS
# shellcheck disable=SC2086
docker compose -f "$OBS" down $DOWN_FLAGS

echo "All stacks stopped."
