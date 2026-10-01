#!/usr/bin/env bash
# Records an administrator-reviewed migration; it never copies a running database or user data.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$ROOT_DIR/scripts/verify-storage.sh"
# shellcheck disable=SC1090
source "${COMPANY_STORAGE_CONFIG:-/etc/company-storage.conf}"
reviewer="${1:-}"
[[ -n "$reviewer" ]] || { echo "usage: record-migration-complete.sh <reviewer-identity>" >&2; exit 2; }
mapfile -t volumes < <(docker volume ls --format '{{.Name}}' | grep -E '(^|_)(nextcloud-db|nextcloud-data|onlyoffice-(data|logs|cache|db)|portainer-data|duplicati-config|adguard-(work|conf)|stirling-(data|config)|netdata-(config|lib|cache))$' || true)
for destination in "$COMPANY_STORAGE_ROOT/nextcloud/html" "$COMPANY_STORAGE_ROOT/nextcloud/data" "$COMPANY_STORAGE_ROOT/mariadb" "$COMPANY_STORAGE_ROOT/onlyoffice/data" "$COMPANY_STORAGE_ROOT/application-data"; do
  find "$destination" -mindepth 1 -print -quit | grep -q . || { echo "ERROR: destination is empty: $destination" >&2; exit 1; }
done
receipt="$COMPANY_STORAGE_ROOT/.company-migration-complete"
{
  echo 'COMPANY_MIGRATION_RECEIPT_VERSION=1'
  echo "VALIDATED_BY=$reviewer"
  echo "VALIDATED_AT_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for volume in "${volumes[@]}"; do echo "MIGRATED_LEGACY_VOLUME=$volume"; done
  if [[ -n "${COMPANY_LEGACY_NEXTCLOUD_DATA_PATH:-}" && -d "$COMPANY_LEGACY_NEXTCLOUD_DATA_PATH" ]] && find "$COMPANY_LEGACY_NEXTCLOUD_DATA_PATH" -mindepth 1 -print -quit | grep -q .; then
    echo "MIGRATED_LEGACY_PATH=$COMPANY_LEGACY_NEXTCLOUD_DATA_PATH"
  fi
} > "$receipt.tmp"
chmod 0640 "$receipt.tmp"
mv -f "$receipt.tmp" "$receipt"
echo "Migration receipt recorded at $receipt"
