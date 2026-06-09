# Company Private Cloud Infrastructure

> Managed by **Forterix / Jad**
> Confidential — Internal Use Only

---

## Architecture

```
Location A                              Location B
┌──────────────────────┐               ┌──────────────────────┐
│  Server A (i3 12th)  │               │  Server B (i3 12th)  │
│  files.company.com   │               │  files.company.com   │
│  Ubuntu 24.04        │               │  Ubuntu 24.04        │
│  Docker + Traefik    │◄─ Tailscale ─►│  Docker + Traefik    │
└──────────────────────┘               └──────────────────────┘
         ▲                                       ▲
         └──────────── Cloudflare DNS ───────────┘
                              ▲
                    [Employees — anywhere]
```

---

## Services

| Service | URL | Purpose |
|---------|-----|---------|
| Nextcloud | files.company.com | File storage, sync, sharing |
| ONLYOFFICE | office.company.com | Browser-based Word/Excel/PowerPoint editing |
| Portainer | portainer.company.com | Container management (developer) |
| Netdata | monitor.company.com | Server monitoring (developer + CEO) |
| Duplicati | backup.company.com | Automated backups |
| AdGuard | dns.company.com | Local DNS |
| Stirling PDF | pdf.company.com | PDF tools |
| Traefik | traefik.company.com | Reverse proxy dashboard |

---

## Stack

| Layer | Technology |
|-------|-----------|
| OS | Ubuntu 24.04 LTS |
| Containers | Docker + Docker Compose |
| Reverse Proxy | Traefik v3 |
| DNS + DDoS | Cloudflare |
| VPN | Tailscale |
| Database | MariaDB 11 |
| Cache | Redis 7 |
| Auto Updates | Watchtower (excludes Nextcloud + ONLYOFFICE) |
| Provisioning | Ansible |
| CI/CD | GitHub Actions |

---

## Deployment

Push to `main` → GitHub Actions auto-deploys to both servers.

```bash
git add .
git commit -m "update: service name - what changed"
git push origin main
```

Both servers update automatically. Check Actions tab for deploy logs.

---

## First Time Setup

See `ansible/README.md` for complete step-by-step guide.

**Quick summary:**
```bash
# 1. Run Ansible on fresh Ubuntu server
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml

# 2. Copy and fill .env on each server
cp .env.example .env && nano .env

# 3. Start Traefik first (handles SSL for everything)
cd services/traefik && docker compose up -d

# 4. Start all other services
cd services/nextcloud && docker compose up -d
cd services/onlyoffice && docker compose up -d
cd services/portainer && docker compose up -d
cd services/netdata && docker compose up -d
cd services/duplicati && docker compose up -d
cd services/adguard && docker compose up -d
cd services/watchtower && docker compose up -d
cd services/stirling-pdf && docker compose up -d

# 5. Connect Tailscale
tailscale up --authkey=YOUR_AUTH_KEY
```

---

## GitHub Secrets Required

| Secret | Value |
|--------|-------|
| `SERVER_A_IP` | Tailscale IP of Server A |
| `SERVER_B_IP` | Tailscale IP of Server B |
| `SERVER_USER` | ubuntu |
| `SSH_PRIVATE_KEY` | Contents of ~/.ssh/company_server_key |

---

## Manual Update Procedure (Nextcloud + ONLYOFFICE)

These two are excluded from Watchtower auto-updates.
Update manually and carefully:

```bash
# 1. Backup first
cd services/duplicati
# Trigger manual backup via UI before updating

# 2. Update Nextcloud
cd services/nextcloud
docker compose pull
docker compose up -d

# 3. Run Nextcloud upgrade
docker exec -u www-data nextcloud php occ upgrade

# 4. Update ONLYOFFICE
cd services/onlyoffice
docker compose pull
docker compose up -d
```

---

## Security Notes

- `.env` file is never committed — lives on server only
- All passwords in GitHub Secrets
- SSH key auth only — no password login
- UFW blocks all ports except 80, 443, 22, 53
- Fail2ban bans IPs after 5 failed SSH attempts
- All traffic HTTPS via Traefik + Let's Encrypt
- Cloudflare hides real server IP
- Tailscale for all admin access

---

## Monthly Cost

| Item | Cost |
|------|------|
| All software | Free (open source) |
| Cloudflare | Free |
| Tailscale (up to 3 admins) | Free |
| Backblaze B2 × 2 servers | ~$12/month |
| Domain | ~$10/year |
| **Total** | **~$12/month** |
