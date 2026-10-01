#!/usr/bin/env bash
# Safe post-deploy checks. It reports failures but does not restart or modify data.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$ROOT_DIR/scripts/production-preflight.sh"
set -a
# Values are required for the TLS check only; do not print this file or its values.
source "$ROOT_DIR/.env"
set +a
compose=(docker compose --env-file "$ROOT_DIR/.env" -f "$ROOT_DIR/services/nextcloud/docker-compose.yml")
"${compose[@]}" exec -T nextcloud-db mariadb-admin ping -h localhost --silent
"${compose[@]}" exec -T nextcloud-redis redis-cli ping | grep -qx PONG
"${compose[@]}" exec -T nextcloud php -r 'exit((int)!@fsockopen("127.0.0.1", 80));'
docker compose --env-file "$ROOT_DIR/.env" -f "$ROOT_DIR/services/onlyoffice/docker-compose.yml" exec -T onlyoffice \
  bash -c 'wget -q --spider http://127.0.0.1/healthcheck || exit 1'
openssl s_client -connect "files.${DOMAIN:?DOMAIN must be set}:443" -servername "$DOMAIN" </dev/null 2>/dev/null | openssl x509 -noout -checkend 2592000
echo "Service checks passed."
