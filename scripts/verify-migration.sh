#!/usr/bin/env bash
# Blocks managed startup when old Docker persistence is present without a reviewed receipt.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$ROOT_DIR/scripts/verify-storage.sh"
# shellcheck disable=SC1090
source "${COMPANY_STORAGE_CONFIG:-/etc/company-storage.conf}"

legacy_suffixes=(nextcloud-db nextcloud-data onlyoffice-data onlyoffice-logs onlyoffice-cache onlyoffice-db portainer-data duplicati-config adguard-work adguard-conf stirling-data stirling-config netdata-config netdata-lib netdata-cache)
mapfile -t all_volumes < <(docker volume ls --format '{{.Name}}')
legacy=()
for volume in "${all_volumes[@]}"; do
  for suffix in "${legacy_suffixes[@]}"; do
    [[ "$volume" == "$suffix" || "$volume" == *"_${suffix}" ]] && legacy+=("$volume") && break
  done
done

legacy_paths=()
if [[ -n "${COMPANY_LEGACY_NEXTCLOUD_DATA_PATH:-}" && -d "$COMPANY_LEGACY_NEXTCLOUD_DATA_PATH" ]] && find "$COMPANY_LEGACY_NEXTCLOUD_DATA_PATH" -mindepth 1 -print -quit | grep -q .; then
  legacy_paths+=("$COMPANY_LEGACY_NEXTCLOUD_DATA_PATH")
fi

if ((${#legacy[@]} == 0 && ${#legacy_paths[@]} == 0)); then
  echo "Migration guard passed: no legacy named volumes detected (fresh installation)."
  exit 0
fi

receipt="$COMPANY_STORAGE_ROOT/.company-migration-complete"
[[ -r "$receipt" ]] || { echo "ERROR: legacy volumes detected (${legacy[*]}); missing $receipt" >&2; exit 1; }
grep -qx 'COMPANY_MIGRATION_RECEIPT_VERSION=1' "$receipt" || { echo "ERROR: invalid migration receipt version" >&2; exit 1; }
for volume in "${legacy[@]}"; do
  grep -Fqx "MIGRATED_LEGACY_VOLUME=$volume" "$receipt" || { echo "ERROR: legacy volume $volume is not recorded as migrated" >&2; exit 1; }
done
for path in "${legacy_paths[@]}"; do
  grep -Fqx "MIGRATED_LEGACY_PATH=$path" "$receipt" || { echo "ERROR: legacy path $path is not recorded as migrated" >&2; exit 1; }
done

# A receipt is accepted only if the destination paths contain migrated state. Any empty
# destination with legacy data is ambiguous and must be reviewed instead of booting empty.
for path in "$COMPANY_STORAGE_ROOT/nextcloud/html" "$COMPANY_STORAGE_ROOT/nextcloud/data" "$COMPANY_STORAGE_ROOT/mariadb" "$COMPANY_STORAGE_ROOT/onlyoffice/data" "$COMPANY_STORAGE_ROOT/application-data"; do
  [[ -d "$path" ]] || { echo "ERROR: migration destination $path is absent" >&2; exit 1; }
  find "$path" -mindepth 1 -print -quit | grep -q . || { echo "ERROR: ambiguous migration; destination is empty: $path" >&2; exit 1; }
done
echo "Migration guard passed: legacy volumes are explicitly recorded for reviewed migration."
