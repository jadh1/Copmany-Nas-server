#!/usr/bin/env bash
# Creates only directories and a readiness sentinel. It never formats, creates, imports,
# encrypts, or destroys a pool. Run only after the hardware/mount decision is documented.
set -euo pipefail
CONFIG_FILE="${COMPANY_STORAGE_CONFIG:-/etc/company-storage.conf}"
[[ -r "$CONFIG_FILE" ]] || { echo "ERROR: missing $CONFIG_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG_FILE"

verify_mount() {
  local path="$1" expected_source="$2" expected_fstype="$3"
  local target source fstype
  [[ "$path" == /* && "$path" != / ]] || { echo "ERROR: unsafe mountpoint $path" >&2; exit 1; }
  target="$(findmnt -M "$path" -n -o TARGET 2>/dev/null || true)"
  source="$(findmnt -M "$path" -n -o SOURCE 2>/dev/null || true)"
  fstype="$(findmnt -M "$path" -n -o FSTYPE 2>/dev/null || true)"
  [[ "$target" == "$path" && "$source" == "$expected_source" && "$fstype" == "$expected_fstype" ]] || {
    echo "ERROR: $path is not the approved exact mountpoint" >&2; exit 1;
  }
}
verify_mount "$COMPANY_STORAGE_ROOT" "$COMPANY_STORAGE_EXPECTED_SOURCE" "$COMPANY_STORAGE_EXPECTED_FSTYPE"
verify_mount "$COMPANY_BACKUP_ROOT" "$COMPANY_BACKUP_EXPECTED_SOURCE" "$COMPANY_BACKUP_EXPECTED_FSTYPE"

for path in \
  "$COMPANY_STORAGE_ROOT/nextcloud/html" "$COMPANY_STORAGE_ROOT/nextcloud/data" \
  "$COMPANY_STORAGE_ROOT/mariadb" "$COMPANY_STORAGE_ROOT/onlyoffice/data" \
  "$COMPANY_STORAGE_ROOT/onlyoffice/logs" "$COMPANY_STORAGE_ROOT/onlyoffice/cache" "$COMPANY_STORAGE_ROOT/onlyoffice/db" \
  "$COMPANY_STORAGE_ROOT/application-data/duplicati" "$COMPANY_STORAGE_ROOT/application-data/portainer" \
  "$COMPANY_STORAGE_ROOT/application-data/adguard/work" "$COMPANY_STORAGE_ROOT/application-data/adguard/conf" \
  "$COMPANY_STORAGE_ROOT/application-data/stirling" "$COMPANY_STORAGE_ROOT/application-data/netdata" \
  "$COMPANY_STORAGE_ROOT/application-data/traefik" "$COMPANY_STORAGE_ROOT/logs/traefik" \
  "$COMPANY_BACKUP_ROOT/mariadb" "$COMPANY_BACKUP_ROOT/restore-tests"; do
  install -d -m 0750 "$path"
done
touch "$COMPANY_STORAGE_ROOT/application-data/traefik/acme.json"
chmod 0600 "$COMPANY_STORAGE_ROOT/application-data/traefik/acme.json"

cat <<'EOF'
Layout created. Before marking ready, migrate/restore persistent state and validate it.
This script intentionally does not copy Docker named volumes or create a snapshot policy.
EOF
if [[ "${1:-}" == "--mark-ready" ]]; then
  touch "$COMPANY_STORAGE_ROOT/.company-storage-ready"
  chmod 0640 "$COMPANY_STORAGE_ROOT/.company-storage-ready"
  echo "Readiness sentinel created. Record validation in INFRASTRUCTURE.md checklist."
fi
