#!/usr/bin/env bash
# One-time cutover action: remove Docker boot resurrection from known managed containers.
set -euo pipefail
containers=(traefik nextcloud nextcloud-db nextcloud-redis onlyoffice duplicati portainer netdata adguard stirling-pdf watchtower)
for container in "${containers[@]}"; do
  if docker container inspect "$container" >/dev/null 2>&1; then
    docker update --restart=no "$container" >/dev/null
    echo "Disabled Docker restart policy for $container"
  fi
done
