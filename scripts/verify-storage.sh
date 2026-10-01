#!/usr/bin/env bash
# Fail closed: never let a bind mount masquerade as mounted company storage.
set -euo pipefail

CONFIG_FILE="${COMPANY_STORAGE_CONFIG:-/etc/company-storage.conf}"
if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "ERROR: missing $CONFIG_FILE; storage has not been approved/configured." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

required=(COMPANY_STORAGE_ROOT COMPANY_STORAGE_EXPECTED_SOURCE COMPANY_STORAGE_EXPECTED_FSTYPE COMPANY_BACKUP_ROOT COMPANY_BACKUP_EXPECTED_SOURCE COMPANY_BACKUP_EXPECTED_FSTYPE)
for name in "${required[@]}"; do
  [[ -n "${!name:-}" ]] || { echo "ERROR: $name is empty in $CONFIG_FILE" >&2; exit 1; }
done

verify_mount() {
  local path="$1" expected_source="$2" expected_fstype="$3"
  local target source fstype
  [[ "$path" == /* && "$path" != / ]] || { echo "ERROR: $path must be a non-root absolute mountpoint" >&2; return 1; }
  [[ -d "$path" ]] || { echo "ERROR: required directory $path is absent" >&2; return 1; }
  target="$(findmnt -M "$path" -n -o TARGET 2>/dev/null || true)"
  source="$(findmnt -M "$path" -n -o SOURCE 2>/dev/null || true)"
  fstype="$(findmnt -M "$path" -n -o FSTYPE 2>/dev/null || true)"
  [[ "$target" == "$path" && "$source" == "$expected_source" && "$fstype" == "$expected_fstype" ]] || {
    echo "ERROR: $path is not the approved exact mountpoint; target='$target' source='$source' fstype='$fstype'" >&2
    return 1
  }
}

verify_mount "$COMPANY_STORAGE_ROOT" "$COMPANY_STORAGE_EXPECTED_SOURCE" "$COMPANY_STORAGE_EXPECTED_FSTYPE"
verify_mount "$COMPANY_BACKUP_ROOT" "$COMPANY_BACKUP_EXPECTED_SOURCE" "$COMPANY_BACKUP_EXPECTED_FSTYPE"

for path in \
  "$COMPANY_STORAGE_ROOT/nextcloud/html" \
  "$COMPANY_STORAGE_ROOT/nextcloud/data" \
  "$COMPANY_STORAGE_ROOT/mariadb" \
  "$COMPANY_STORAGE_ROOT/onlyoffice/data" \
  "$COMPANY_STORAGE_ROOT/onlyoffice/logs" \
  "$COMPANY_STORAGE_ROOT/onlyoffice/cache" \
  "$COMPANY_STORAGE_ROOT/onlyoffice/db" \
  "$COMPANY_STORAGE_ROOT/application-data" \
  "$COMPANY_STORAGE_ROOT/logs" \
  "$COMPANY_STORAGE_ROOT/logs/traefik" \
  "$COMPANY_BACKUP_ROOT"; do
  [[ -d "$path" ]] || { echo "ERROR: required storage layout path $path is absent" >&2; exit 1; }
done

[[ -f "$COMPANY_STORAGE_ROOT/.company-storage-ready" ]] || {
  echo "ERROR: missing storage readiness sentinel. Complete migration/restore validation before creating it." >&2
  exit 1
}

echo "Storage guard passed: $COMPANY_STORAGE_ROOT and $COMPANY_BACKUP_ROOT are verified mounts."
