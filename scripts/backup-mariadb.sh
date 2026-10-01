#!/usr/bin/env bash
# Application-consistent logical backup. Requires a verified backup mount and a running DB.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$ROOT_DIR/scripts/production-preflight.sh"
# shellcheck disable=SC1090
source "${COMPANY_STORAGE_CONFIG:-/etc/company-storage.conf}"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output_dir="$COMPANY_BACKUP_ROOT/mariadb"
output_file="$output_dir/nextcloud-$timestamp.sql.gz"
temporary_file="$output_file.partial"
temporary_manifest="$temporary_file.sha256"
manifest="$output_file.sha256"
install -d -m 0750 "$output_dir"
trap 'rm -f "$temporary_file" "$temporary_manifest"' EXIT

docker compose --env-file "$ROOT_DIR/.env" -f "$ROOT_DIR/services/nextcloud/docker-compose.yml" \
  exec -T nextcloud-db sh -ec 'mariadb-dump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines --events --databases nextcloud' \
  | gzip -9 > "$temporary_file"
gzip -t "$temporary_file"
test -s "$temporary_file"

uncompressed_head="$(gzip -dc "$temporary_file" | head -c 2048)"
[[ -n "$uncompressed_head" ]] || { echo "ERROR: uncompressed MariaDB dump is empty" >&2; exit 1; }
echo "$uncompressed_head" | grep -Eq 'CREATE DATABASE|USE |MariaDB dump|Table structure' || {
  echo "ERROR: uncompressed dump does not contain valid database SQL statements" >&2
  exit 1
}

sha256=$(sha256sum "$temporary_file" | awk '{print $1}')
echo "$sha256  $(basename "$output_file")" > "$temporary_manifest"
mv -f "$temporary_file" "$output_file"
mv -f "$temporary_manifest" "$manifest"
trap - EXIT
echo "Validated MariaDB dump written to $output_file"
