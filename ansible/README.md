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

### 5. Configure Storage and Access Facts
Copy `group_vars/all.yml.example` to `group_vars/all.yml`:
```bash
cp group_vars/all.yml.example group_vars/all.yml
nano group_vars/all.yml
```
Record the approved mount sources, filesystems, and Tailscale access settings.

### 6. Run Ansible Playbook
```bash
cd ansible
ansible-playbook -i inventory.ini playbook.yml
```

### 7. Configure Server Environment
```bash
ssh ubuntu@SERVER_A_IP
cp /opt/server/.env.example /opt/server/.env
nano /opt/server/.env   # fill in all values matching storage & Tailscale facts
```

### 8. Connect Tailscale
```bash
sudo tailscale up --authkey=YOUR_AUTH_KEY
```

### 9. Verify Storage and Start Managed Services
Do not run direct `docker compose up -d` (production services require the `managed` profile and storage validation):
```bash
# Run production preflight check
/opt/server/scripts/production-preflight.sh

# Start all applications via the systemd lifecycle
sudo systemctl start company-applications.service

# Verify health status
sudo systemctl status company-applications.service
```

## After Setup — Services Available At

| Service | Scope | URL |
|---------|-------|-----|
| Files (Nextcloud) | Public HTTPS (443) | `https://files.company.com` |
| Document Editing (ONLYOFFICE) | Public HTTPS (443) | `https://office.company.com` |
| Monitoring (Netdata) | Tailnet Only (8443) | `https://monitor.company.com:8443` |
| Backups (Duplicati) | Tailnet Only (8443) | `https://backup.company.com:8443` |
| DNS Management (AdGuard) | Tailnet Only (8443) | `https://dns.company.com:8443` |
| PDF Tools (Stirling PDF) | Tailnet Only (8443) | `https://pdf.company.com:8443` |
| Container Admin (Portainer) | Tailnet Only (8443) | `https://portainer.company.com:8443` |
| Reverse Proxy (Traefik) | Tailnet Only (8443) | `https://traefik.company.com:8443` |
