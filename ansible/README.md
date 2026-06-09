# First Time Server Setup

## Prerequisites (on your PC)
```bash
pip install ansible
```

## Steps

### 1. Generate SSH key for servers
```bash
ssh-keygen -t ed25519 -C "company-server" -f ~/.ssh/company_server_key
```

### 2. Copy public key to both servers
```bash
ssh-copy-id -i ~/.ssh/company_server_key.pub ubuntu@SERVER_A_IP
ssh-copy-id -i ~/.ssh/company_server_key.pub ubuntu@SERVER_B_IP
```

### 3. Add private key to GitHub Secrets
- Go to GitHub repo → Settings → Secrets → Actions
- Add: `SSH_PRIVATE_KEY` → paste contents of `~/.ssh/company_server_key`
- Add: `SERVER_A_IP` → IP of Server A
- Add: `SERVER_B_IP` → IP of Server B
- Add: `SERVER_USER` → ubuntu

### 4. Update inventory.ini
Replace `SERVER_A_IP` and `SERVER_B_IP` with real IPs.

### 5. Run Ansible playbook (installs everything)
```bash
cd ansible
ansible-playbook -i inventory.ini playbook.yml
```

### 6. Copy .env.example to .env on each server
```bash
ssh ubuntu@SERVER_A_IP
cp /opt/server/.env.example /opt/server/.env
nano /opt/server/.env   # fill in all values
```

### 7. Start Traefik first
```bash
cd /opt/server/services/traefik
docker compose up -d
```

### 8. Start all other services
```bash
cd /opt/server/services/nextcloud && docker compose up -d
cd /opt/server/services/portainer && docker compose up -d
cd /opt/server/services/netdata && docker compose up -d
cd /opt/server/services/duplicati && docker compose up -d
cd /opt/server/services/adguard && docker compose up -d
cd /opt/server/services/watchtower && docker compose up -d
cd /opt/server/services/stirling-pdf && docker compose up -d
```

### 9. Connect Tailscale
```bash
tailscale up --authkey=YOUR_AUTH_KEY
```

## After Setup — Services Available At

| Service | URL |
|---------|-----|
| Files | https://files.company.com |
| Monitoring | https://monitor.company.com |
| Backups | https://backup.company.com |
| DNS | https://dns.company.com |
| PDF Tools | https://pdf.company.com |
| Portainer | https://portainer.company.com |
| Traefik | https://traefik.company.com |
