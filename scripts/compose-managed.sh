#!/usr/bin/env bash
# Runs one managed Compose service only after the complete production preflight.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
service="${1:?usage: compose-managed.sh <service> <compose arguments...>}"
shift
bash "$ROOT_DIR/scripts/production-preflight.sh"
# shellcheck disable=SC1090
source "${COMPANY_STORAGE_CONFIG:-/etc/company-storage.conf}"
set -a
source "$ROOT_DIR/.env"
set +a
export STORAGE_ROOT="$COMPANY_STORAGE_ROOT" BACKUP_ROOT="$COMPANY_BACKUP_ROOT"
exec docker compose --profile managed --env-file "$ROOT_DIR/.env" -f "$ROOT_DIR/services/$service/docker-compose.yml" "$@"
