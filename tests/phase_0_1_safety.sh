#!/usr/bin/env bash
# Non-destructive regression harness. It uses temporary directories and mocked host commands.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fixture="$tmp/repo"
mkdir -p "$fixture"
cp -R "$ROOT_DIR/scripts" "$fixture/scripts"
chmod +x "$fixture/scripts"/*.sh
mkdir -p "$tmp/bin"

fail() { echo "FAIL: $*" >&2; exit 1; }
expect_fail() { "$@" >/dev/null 2>&1 && fail "expected failure: $*" || true; }
prepare_layout() {
  local root="$1" backup="$2"
  mkdir -p "$root/nextcloud/html" "$root/nextcloud/data" "$root/mariadb" "$root/onlyoffice/data" "$root/onlyoffice/logs" "$root/onlyoffice/cache" "$root/onlyoffice/db" "$root/application-data" "$root/logs/traefik" "$backup/mariadb"
  touch "$root/.company-storage-ready"
}
write_config() {
  cat > "$tmp/storage.conf" <<EOF
COMPANY_STORAGE_ROOT=$1
COMPANY_STORAGE_EXPECTED_SOURCE=company
COMPANY_STORAGE_EXPECTED_FSTYPE=zfs
COMPANY_BACKUP_ROOT=$2
COMPANY_BACKUP_EXPECTED_SOURCE=backup
COMPANY_BACKUP_EXPECTED_FSTYPE=zfs
COMPANY_LEGACY_NEXTCLOUD_DATA_PATH=
EOF
}
cat > "$tmp/bin/findmnt" <<'EOF'
#!/usr/bin/env bash
path="$2"; output="${@: -1}"
if [[ "${FINDMNT_EXACT:-0}" != 1 ]]; then exit 1; fi
case "$output" in TARGET) printf '%s\n' "$path";; SOURCE) [[ "$path" == *backup* ]] && echo backup || echo company;; FSTYPE) echo zfs;; esac
EOF
cat > "$tmp/bin/ip" <<'EOF'
#!/usr/bin/env bash
echo '7: tailscale0    inet 100.64.0.9/32 scope global tailscale0'
EOF
cat > "$tmp/bin/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == volume ]]; then printf '%s\n' "${MOCK_LEGACY_VOLUME:-}"; exit 0; fi
if [[ "$1" == compose ]]; then
  case " $* " in
    *' exec '*) if [[ "${MOCK_DUMP_FAIL:-0}" == 1 ]]; then printf partial; exit 1; fi; if [[ "${MOCK_DUMP_EMPTY:-0}" == 1 ]]; then exit 0; fi; printf 'CREATE DATABASE nextcloud;'; exit 0;;
    *) exit 0;;
  esac
fi
exit 0
EOF
chmod +x "$tmp/bin"/*

storage="$tmp/storage"; backup="$tmp/backup"; prepare_layout "$storage" "$backup"; write_config "$storage" "$backup"
PATH="$tmp/bin:$PATH" COMPANY_STORAGE_CONFIG="$tmp/storage.conf" FINDMNT_EXACT=0 expect_fail "$fixture/scripts/verify-storage.sh"
echo 'PASS storage ordinary directory rejected'
PATH="$tmp/bin:$PATH" COMPANY_STORAGE_CONFIG="$tmp/storage.conf" FINDMNT_EXACT=1 "$fixture/scripts/verify-storage.sh" >/dev/null
echo 'PASS exact simulated mount accepted'
sed -i 's/COMPANY_STORAGE_EXPECTED_SOURCE=company/COMPANY_STORAGE_EXPECTED_SOURCE=wrong-company/' "$tmp/storage.conf"
PATH="$tmp/bin:$PATH" COMPANY_STORAGE_CONFIG="$tmp/storage.conf" FINDMNT_EXACT=1 expect_fail "$fixture/scripts/verify-storage.sh"
echo 'PASS wrong dedicated mount identity rejected'
write_config "$storage" "$backup"
write_config / "$backup"
PATH="$tmp/bin:$PATH" COMPANY_STORAGE_CONFIG="$tmp/storage.conf" FINDMNT_EXACT=1 expect_fail "$fixture/scripts/verify-storage.sh"
echo 'PASS root storage path rejected'
write_config "$storage" "$backup"

write_config "$storage" "$backup"
cat > "$fixture/.env" <<EOF
STORAGE_ROOT=$storage
BACKUP_ROOT=$backup
TAILSCALE_ADMIN_BIND_IP=100.64.0.9
EOF
PATH="$tmp/bin:$PATH" COMPANY_STORAGE_CONFIG="$tmp/storage.conf" FINDMNT_EXACT=1 "$fixture/scripts/production-preflight.sh" >/dev/null
echo 'PASS authoritative root binding accepted'
sed -i "s|^STORAGE_ROOT=.*|STORAGE_ROOT=$tmp/other|" "$fixture/.env"
PATH="$tmp/bin:$PATH" COMPANY_STORAGE_CONFIG="$tmp/storage.conf" FINDMNT_EXACT=1 expect_fail "$fixture/scripts/production-preflight.sh"
echo 'PASS mismatched Compose root rejected'
sed -i "s|^STORAGE_ROOT=.*|STORAGE_ROOT=$storage|" "$fixture/.env"
grep -v '^STORAGE_ROOT=' "$fixture/.env" > "$fixture/.env.tmp" && mv "$fixture/.env.tmp" "$fixture/.env"
PATH="$tmp/bin:$PATH" COMPANY_STORAGE_CONFIG="$tmp/storage.conf" FINDMNT_EXACT=1 expect_fail "$fixture/scripts/production-preflight.sh"
echo 'PASS missing Compose root rejected'
printf 'STORAGE_ROOT=%s\n' "$storage" >> "$fixture/.env"
write_config . "$backup"
PATH="$tmp/bin:$PATH" COMPANY_STORAGE_CONFIG="$tmp/storage.conf" FINDMNT_EXACT=1 expect_fail "$fixture/scripts/verify-storage.sh"
echo 'PASS relative storage root rejected'
write_config "$storage" "$backup"

MOCK_LEGACY_VOLUME=nextcloud_nextcloud-db PATH="$tmp/bin:$PATH" COMPANY_STORAGE_CONFIG="$tmp/storage.conf" FINDMNT_EXACT=1 expect_fail "$fixture/scripts/verify-migration.sh"
echo 'PASS legacy volume without receipt rejected'
printf 'COMPANY_MIGRATION_RECEIPT_VERSION=1\nMIGRATED_LEGACY_VOLUME=nextcloud_nextcloud-db\n' > "$storage/.company-migration-complete"
MOCK_LEGACY_VOLUME=nextcloud_nextcloud-db PATH="$tmp/bin:$PATH" COMPANY_STORAGE_CONFIG="$tmp/storage.conf" FINDMNT_EXACT=1 expect_fail "$fixture/scripts/verify-migration.sh"
echo 'PASS ambiguous empty migration rejected'
touch "$storage/nextcloud/html/migrated" "$storage/nextcloud/data/migrated" "$storage/mariadb/migrated" "$storage/onlyoffice/data/migrated" "$storage/application-data/migrated"
MOCK_LEGACY_VOLUME=nextcloud_nextcloud-db PATH="$tmp/bin:$PATH" COMPANY_STORAGE_CONFIG="$tmp/storage.conf" FINDMNT_EXACT=1 "$fixture/scripts/verify-migration.sh" >/dev/null
echo 'PASS reviewed legacy migration accepted'

rm -f "$backup/mariadb"/*
MOCK_DUMP_FAIL=1 PATH="$tmp/bin:$PATH" COMPANY_STORAGE_CONFIG="$tmp/storage.conf" FINDMNT_EXACT=1 "$fixture/scripts/backup-mariadb.sh" >/dev/null 2>&1 && fail 'failed dump reported success'
[[ -z "$(find "$backup/mariadb" -type f -name '*.sql.gz' -print -quit)" ]] || fail 'failed dump left final backup artifact'
echo 'PASS failed dump leaves no final backup artifact'

MOCK_DUMP_EMPTY=1 PATH="$tmp/bin:$PATH" COMPANY_STORAGE_CONFIG="$tmp/storage.conf" FINDMNT_EXACT=1 "$fixture/scripts/backup-mariadb.sh" >/dev/null 2>&1 && fail 'empty dump reported success'
[[ -z "$(find "$backup/mariadb" -type f -name '*.sql.gz' -print -quit)" ]] || fail 'empty dump left final backup artifact'
echo 'PASS empty dump is rejected and leaves no final backup artifact'

MOCK_DUMP_FAIL=0 MOCK_DUMP_EMPTY=0 PATH="$tmp/bin:$PATH" COMPANY_STORAGE_CONFIG="$tmp/storage.conf" FINDMNT_EXACT=1 "$fixture/scripts/backup-mariadb.sh" >/dev/null
find "$backup/mariadb" -type f -name '*.sql.gz' -print -quit | grep -q . || fail 'successful dump has no final artifact'
manifest_name="$(basename "$(find "$backup/mariadb" -type f -name '*.sha256' -print -quit)")"
(cd "$backup/mariadb" && sha256sum -c "$manifest_name") >/dev/null || fail 'manifest verification failed'
echo 'PASS successful dump atomically creates final backup artifact with valid checksum manifest'

for compose in "$ROOT_DIR"/services/*/docker-compose.yml; do
  grep -q 'profiles: \["managed"\]' "$compose" || [[ "$compose" == *watchtower* ]] || fail "missing managed profile: $compose"
  grep -q 'restart: "no"' "$compose" || [[ "$compose" == *watchtower* ]] || fail "Docker restart bypass remains: $compose"
done
echo 'PASS stateful Compose services require managed lifecycle and disable Docker restart'
