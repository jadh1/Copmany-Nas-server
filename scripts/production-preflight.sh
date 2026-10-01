#!/usr/bin/env bash
# The only supported production preflight. It binds authoritative storage facts to Compose.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$ROOT_DIR/scripts/verify-storage.sh"
bash "$ROOT_DIR/scripts/verify-migration.sh"
# shellcheck disable=SC1090
source "${COMPANY_STORAGE_CONFIG:-/etc/company-storage.conf}"
[[ -r "$ROOT_DIR/.env" ]] || { echo "ERROR: missing $ROOT_DIR/.env" >&2; exit 1; }
set -a
source "$ROOT_DIR/.env"
set +a

[[ "${STORAGE_ROOT:-}" == "$COMPANY_STORAGE_ROOT" ]] || { echo "ERROR: .env STORAGE_ROOT must equal approved storage root" >&2; exit 1; }
[[ "${BACKUP_ROOT:-}" == "$COMPANY_BACKUP_ROOT" ]] || { echo "ERROR: .env BACKUP_ROOT must equal approved backup root" >&2; exit 1; }
[[ "${STORAGE_ROOT:-}" == /* && "$STORAGE_ROOT" != / ]] || { echo "ERROR: unsafe STORAGE_ROOT" >&2; exit 1; }
[[ "${BACKUP_ROOT:-}" == /* && "$BACKUP_ROOT" != / ]] || { echo "ERROR: unsafe BACKUP_ROOT" >&2; exit 1; }
[[ -n "${TAILSCALE_ADMIN_BIND_IP:-}" ]] || { echo "ERROR: TAILSCALE_ADMIN_BIND_IP is required" >&2; exit 1; }
ip -o -4 addr show dev tailscale0 | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "$TAILSCALE_ADMIN_BIND_IP" || {
  echo "ERROR: TAILSCALE_ADMIN_BIND_IP is not assigned to tailscale0" >&2; exit 1;
}

export STORAGE_ROOT="$COMPANY_STORAGE_ROOT" BACKUP_ROOT="$COMPANY_BACKUP_ROOT" TAILSCALE_ADMIN_BIND_IP
for service in traefik nextcloud onlyoffice duplicati portainer netdata adguard stirling-pdf; do
  docker compose --profile managed --env-file "$ROOT_DIR/.env" -f "$ROOT_DIR/services/$service/docker-compose.yml" config --quiet
done
echo "Production preflight passed."
