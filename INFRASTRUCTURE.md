# Private Company Cloud Infrastructure

Comprehensive technical architecture, operational runbooks, storage engineering, security controls, and deployment manual for the Private Company Cloud platform.

---

## Table of Contents

1. [Purpose and Scope](#1-purpose-and-scope)
2. [Current Engineering Status](#2-current-engineering-status)
3. [System Architecture](#3-system-architecture)
4. [Service Inventory](#4-service-inventory)
5. [Network Architecture and Ingress](#5-network-architecture-and-ingress)
6. [Storage Architecture and Data Integrity](#6-storage-architecture-and-data-integrity)
7. [Startup Lifecycle and Process Control](#7-startup-lifecycle-and-process-control)
8. [Migration and Legacy State Handling](#8-migration-and-legacy-state-handling)
9. [Backup Architecture](#9-backup-architecture)
10. [Disaster Recovery and Failure Scenarios](#10-disaster-recovery-and-failure-scenarios)
11. [Security Architecture and Access Boundaries](#11-security-architecture-and-access-boundaries)
12. [Deployment Architecture](#12-deployment-architecture)
13. [Monitoring and Telemetry](#13-monitoring-and-telemetry)
14. [Hardware Requirements and Sizing](#14-hardware-requirements-and-sizing)
15. [Administrator Runbook](#15-administrator-runbook)
16. [Production Readiness Checklist](#16-production-readiness-checklist)
17. [Live-Host Validation Checklist](#17-live-host-validation-checklist)
18. [Known Operational Limitations](#18-known-operational-limitations)
19. [Future Architectural Roadmap](#19-future-architectural-roadmap)

---

## 1. Purpose and Scope

The Private Company Cloud is a dedicated, self-hosted file-collaboration and internal-services platform designed for enterprise data ownership. Built upon Nextcloud, ONLYOFFICE Document Server, containerized infrastructure utilities, and strict storage-gated host orchestration, the platform provides:

- Document storage, synchronization, sharing, and versioning for employees.
- Real-time multi-user document, spreadsheet, and presentation editing in web browsers.
- Reverse proxy routing with automated ACME TLS certificate lifecycle management.
- Network-isolated administrative tooling (container management, host telemetry, DNS filtering, PDF processing, backup orchestration).
- Fail-closed storage and lifecycle controls to prevent data loss or silent filesystem corruption.

**Scope:** This document is the authoritative technical reference for host architecture, storage requirements, security boundaries, deployment procedures, operational runbooks, and disaster-recovery protocols.

---

## 2. Current Engineering Status

| Dimension | Status | Notes |
|---|---|---|
| **Repository Baseline** | **VERIFIED** | Static code analysis, shell syntax, Docker Compose definitions, YAML parsing, regression tests, and secret scans pass cleanly. |
| **Fail-Closed Storage Guard** | **VERIFIED** | Mount verification uses Linux `findmnt -M`, enforcing dedicated mountpoints, non-root paths, and matching filesystem/source identities. |
| **Lifecycle Autostart Prevention** | **VERIFIED** | All production stateful services require `--profile managed` and set `restart: "no"`. Unprofiled Compose invocations fail closed. |
| **Administrative Network Isolation** | **VERIFIED (Config)** | Port 8443 binds strictly to the host's `tailscale0` IPv4 address (`TAILSCALE_ADMIN_BIND_IP`). No public exposure on 8443. |
| **Deployment Automation** | **VERIFIED** | Serial canary rollout via GitHub Actions. Worktree-isolated preflights guarantee that only validated commit SHAs are deployed. |
| **MariaDB Backup Atomicity** | **VERIFIED** | Validates uncompressed SQL dump contents, verifies gzip integrity, records relative SHA-256 manifest, and finalizes via atomic rename. |
| **Physical Storage Hardware** | **PENDING LIVE HOST** | Requires dedicated physical disks, RAID/ZFS pool provisioning, and UPS integration. |
| **Live Reboot & Daemon Behavior** | **PENDING LIVE HOST** | Requires physical reboot validation to verify systemd service ordering and Docker daemon restart behavior. |
| **External Network Reachability** | **PENDING LIVE HOST** | Requires live dual-stack (IPv4/IPv6) firewall and penetration testing from untrusted public networks. |
| **Offsite Immutable Backup** | **PENDING LIVE HOST** | Requires Backblaze B2 bucket provisioning, Object Lock configuration, and restore drills. |
| **Production Certification** | **NOT READY** | Production deployment is blocked until isolated live-host testing is complete. |

---

## 3. System Architecture

The platform operates as a single-primary-node deployment per site with separate canary deployment targets. It intentionally avoids distributed clustering, distributed locking, or split-brain risks.

```mermaid
flowchart TD
    subgraph PublicInternet["Public Internet (WAN)"]
        UserClient["Company Employees\n(Browser / Desktop / Mobile)"]
    end

    subgraph TailnetAdmin["Encrypted Tailnet (Tailscale)"]
        AdminClient["Company Administrators\n(Authorized Nodes Only)"]
    end

    subgraph HostSystem["Production Server Host"]
        subgraph IngressLayer["Ingress & Edge Routing"]
            TraefikPublic["Traefik Reverse Proxy\nPorts: 80, 443 (0.0.0.0)\nTLS (Let's Encrypt ACME)"]
            TraefikAdmin["Traefik Admin Router\nPort: 8443 (tailscale0 IP only)\nEntrypoint: admin"]
        end

        subgraph CoreApps["Core Application Services"]
            NextcloudApp["Nextcloud App Server\nPHP-FPM / Apache (Port 80)"]
            OnlyOfficeApp["ONLYOFFICE Document Server\nJWT Authentication (Port 80)"]
        end

        subgraph PrivateData["Private Data Tier (Internal Network)"]
            MariaDB["MariaDB 11\nRow Binlog / Read Committed"]
            Redis["Redis 7\nTransactional Locking & Cache"]
        end

        subgraph AdminTools["Isolated Administrative Tools (Admin Router Only)"]
            Portainer["Portainer CE (Port 9000)"]
            Netdata["Netdata Metrics (Port 19999)"]
            Duplicati["Duplicati Backup UI (Port 8200)"]
            AdGuard["AdGuard Home DNS (Port 80)"]
            StirlingPDF["Stirling PDF (Port 8080)"]
        end

        subgraph StorageSubsystem["Dedicated Storage Subsystem"]
            StoragePool["Approved Storage Pool\n(ZFS Mirror / RAIDZ2)\nSTORAGE_ROOT: /mnt/company"]
            BackupPool["Approved Backup Pool\nBACKUP_ROOT: /mnt/company-backup"]
        end
    end

    subgraph OffsiteCloud["Offsite Disaster Recovery (Target)"]
        B2["Backblaze B2\nObject Lock / Immutable Retention"]
    end

    UserClient -->|HTTPS:443| TraefikPublic
    AdminClient -->|HTTPS:8443| TraefikAdmin

    TraefikPublic --> NextcloudApp
    TraefikPublic --> OnlyOfficeApp

    TraefikAdmin --> Portainer
    TraefikAdmin --> Netdata
    TraefikAdmin --> Duplicati
    TraefikAdmin --> AdGuard
    TraefikAdmin --> StirlingPDF

    NextcloudApp <-->|SQL| MariaDB
    NextcloudApp <-->|Cache / Locks| Redis
    NextcloudApp <-->|JWT / REST| OnlyOfficeApp

    NextcloudApp -->|Bind Mount| StoragePool
    MariaDB -->|Bind Mount| StoragePool
    OnlyOfficeApp -->|Bind Mount| StoragePool
    AdminTools -->|Bind Mount| StoragePool

    MariaDB -.->|Daily Logical Dump| BackupPool
    Duplicati -.->|Staged File Backup| BackupPool
    Duplicati -.->|Encrypted Upload (Future)| B2
```

---

## 4. Service Inventory

All production services run as isolated Docker containers within managed bridge networks.

| Service | Container Name | Purpose | Ingress / Exposure | Persistent State Location | Dependencies |
|---|---|---|---|---|---|
| **Traefik** | `traefik` | Edge reverse proxy, TLS termination, routing | Ports `80:80`, `443:443` (Public); Port `8443` (`tailscale0` IP) | `${STORAGE_ROOT}/application-data/traefik/acme.json`<br>`${STORAGE_ROOT}/logs/traefik/` | Host network, Docker socket (`:ro`) |
| **Nextcloud** | `nextcloud` | File collaboration, sync, web interface | Internal `proxy` network; routed via `files.${DOMAIN}` | `${STORAGE_ROOT}/nextcloud/html`<br>`${STORAGE_ROOT}/nextcloud/data` | `nextcloud-db` (healthy), `nextcloud-redis` (healthy) |
| **MariaDB** | `nextcloud-db` | Relational database for Nextcloud | Internal `nextcloud-internal` network only | `${STORAGE_ROOT}/mariadb` | Storage mount |
| **Redis** | `nextcloud-redis` | In-memory caching and file-locking | Internal `nextcloud-internal` network only | None (in-memory, disposable) | None |
| **ONLYOFFICE** | `onlyoffice` | Real-time web document editor | Internal `proxy` network; routed via `office.${DOMAIN}` | `${STORAGE_ROOT}/onlyoffice/data`<br>`${STORAGE_ROOT}/onlyoffice/db`<br>`${STORAGE_ROOT}/onlyoffice/logs`<br>`${STORAGE_ROOT}/onlyoffice/cache` | JWT secret integration |
| **Portainer** | `portainer` | Container runtime management | Internal `proxy` network; routed via `portainer.${DOMAIN}:8443` | `${STORAGE_ROOT}/application-data/portainer` | Docker socket (`:ro`) |
| **Netdata** | `netdata` | Real-time host telemetry and health | Internal `proxy` network; routed via `monitor.${DOMAIN}:8443` | `${STORAGE_ROOT}/application-data/netdata/config`<br>`${STORAGE_ROOT}/application-data/netdata/lib`<br>`netdata-cache` (named volume) | Host PID, `/proc`, `/sys`, Docker socket (`:ro`) |
| **Duplicati** | `duplicati` | Backup scheduling and encryption | Internal `proxy` network; routed via `backup.${DOMAIN}:8443` | `${STORAGE_ROOT}/application-data/duplicati` | Storage root (`:ro`), Backup root (`:rw`) |
| **AdGuard Home** | `adguard` | Network DNS filtering and caching | Admin UI on `:8443`; DNS on `53:53/tcp+udp` (LAN restricted) | `${STORAGE_ROOT}/application-data/adguard/work`<br>`${STORAGE_ROOT}/application-data/adguard/conf` | UFW allow rules for approved LAN ranges |
| **Stirling PDF** | `stirling-pdf` | Document processing and OCR | Internal `proxy` network; routed via `pdf.${DOMAIN}:8443` | `${STORAGE_ROOT}/application-data/stirling/tessdata`<br>`${STORAGE_ROOT}/application-data/stirling/config` | Security enabled (`DOCKER_ENABLE_SECURITY=true`) |
| **Watchtower** | `watchtower` | Scheduled image update monitor (Disabled) | Profile `manual-updates`; monitor-only | None | Docker socket (`:rw`) |

---

## 5. Network Architecture and Ingress

The platform defines three strict network boundaries:

### 5.1 Public Plane (Internet)
- **Port 80/tcp:** HTTP-01 ACME challenge handling and HTTP-to-HTTPS redirect.
- **Port 443/tcp:** Employee HTTPS traffic terminating on Traefik. Traefik routes exclusively to:
  - `files.${DOMAIN}` → `nextcloud:80` (HSTS enabled, 1-year max-age).
  - `office.${DOMAIN}` → `onlyoffice:80` (HSTS enabled).
- Direct host ports are blocked by host UFW (`ufw default deny incoming`).

### 5.2 Administrative Plane (Tailnet Only)
- **Port 8443/tcp:** Bound strictly to the IP assigned to `tailscale0` via `"${TAILSCALE_ADMIN_BIND_IP}:8443:8443"`.
- Traefik exposes the `admin` entrypoint exclusively on port 8443 with TLS termination.
- All administrative routers (`traefik`, `portainer`, `monitor`, `backup`, `dns`, `pdf`) attach to the `admin` entrypoint.
- Host UFW permits TCP 8443 only on interface `tailscale0` (`ufw allow in on tailscale0 to any port 8443 proto tcp`).

### 5.3 Internal Container Networks
- **`proxy` network:** Bridge network connecting Traefik to HTTP backends. Exposed by default: `false`.
- **`nextcloud-internal` network:** Dedicated isolated bridge network (`internal: true`) connecting `nextcloud`, `nextcloud-db`, and `nextcloud-redis`. It has no gateway and cannot route out to the host or internet.

---

## 6. Storage Architecture and Data Integrity

### 6.1 Authoritative Storage Configuration
Host storage is governed by `/etc/company-storage.conf`, provisioned by Ansible and owned by `root:root` (mode `0640`). It defines:

```bash
COMPANY_STORAGE_ROOT=/mnt/company
COMPANY_STORAGE_EXPECTED_SOURCE=company
COMPANY_STORAGE_EXPECTED_FSTYPE=zfs
COMPANY_BACKUP_ROOT=/mnt/company-backup
COMPANY_BACKUP_EXPECTED_SOURCE=backup
COMPANY_BACKUP_EXPECTED_FSTYPE=zfs
COMPANY_LEGACY_NEXTCLOUD_DATA_PATH=/mnt/storage
```

### 6.2 Fail-Closed Verification Mechanics
Before any stateful container can start, `scripts/verify-storage.sh` checks:
1. Both `COMPANY_STORAGE_ROOT` and `COMPANY_BACKUP_ROOT` are absolute, non-root paths (`path != /`).
2. Both directories exist on disk.
3. Linux kernel mount verification via `findmnt -M "$path"`:
   - `TARGET` must equal `$path`.
   - `SOURCE` must match `COMPANY_*_EXPECTED_SOURCE`.
   - `FSTYPE` must match `COMPANY_*_EXPECTED_FSTYPE`.
4. Required directory layout exists.
5. Storage readiness sentinel (`.company-storage-ready`) is present.

If a mount fails to mount during boot, the directory on the root partition is rejected because `findmnt -M` returns empty. The systemd service fails closed and prevents stateful applications from starting.

### 6.3 Directory Layout Standard
```text
/mnt/company/                          # COMPANY_STORAGE_ROOT
├── .company-storage-ready             # Readiness sentinel file (mode 0640)
├── .company-migration-complete        # Migration receipt (if legacy state existed)
├── nextcloud/
│   ├── html/                         # Nextcloud application code & custom apps
│   └── data/                         # Nextcloud user files
├── mariadb/                          # MariaDB datadir (/var/lib/mysql)
├── onlyoffice/
│   ├── data/                         # ONLYOFFICE Document Server data
│   ├── logs/                         # ONLYOFFICE service logs
│   ├── cache/                        # ONLYOFFICE cache
│   └── db/                           # ONLYOFFICE internal PostgreSQL data
├── application-data/
│   ├── traefik/
│   │   └── acme.json                 # Let's Encrypt TLS certificates (mode 0600)
│   ├── duplicati/                    # Duplicati SQLite job databases
│   ├── portainer/                    # Portainer server database
│   ├── netdata/                      # Netdata host config & lib
│   ├── adguard/                      # AdGuard Home config & work directories
│   └── stirling/                     # Stirling PDF configs & tessdata
└── logs/
    └── traefik/                      # Traefik access & error logs

/mnt/company-backup/                   # COMPANY_BACKUP_ROOT
├── mariadb/                          # Atomic logical MariaDB dumps (*.sql.gz + *.sha256)
└── restore-tests/                     # Test recovery staging area
```

---

## 7. Startup Lifecycle and Process Control

### 7.1 Production Startup Chain
Stateful production services cannot start automatically or unmanaged. The startup chain is strictly enforced:

```text
Host Boot
   │
   ▼
local-fs.target (Mount filesystems)
   │
   ▼
company-storage-guard.service (Type=oneshot, verify-storage.sh)
   │ [Storage Guard Passed]
   ▼
company-applications.service
   │
   ├─► ExecStartPre: production-preflight.sh
   │     ├─► verify-storage.sh
   │     ├─► verify-migration.sh
   │     ├─► Verify .env STORAGE_ROOT == COMPANY_STORAGE_ROOT
   │     ├─► Verify TAILSCALE_ADMIN_BIND_IP is assigned to tailscale0
   │     └─► docker compose --profile managed config --quiet
   │
   ├─► ExecStart: compose-managed.sh <service> up -d --remove-orphans
   │     (traefik -> nextcloud -> onlyoffice -> duplicati -> portainer -> netdata -> adguard -> stirling-pdf)
   │
   └─► ExecStartPost: check-services.sh
         (Ping MariaDB, Redis, Nextcloud HTTP, ONLYOFFICE healthcheck, TLS expiration)
```

### 7.2 Docker Autostart Prevention
To prevent Docker from resurrecting containers before storage is verified:
1. All production stateful services declare `restart: "no"`.
2. All production stateful services declare `profiles: ["managed"]`.
3. Running `docker compose up -d` without `--profile managed` outputs `no service selected` (exit 1).
4. Ansible executes `scripts/disable-unmanaged-autostart.sh` during cutover to clear restart policies on legacy containers.

---

## 8. Migration and Legacy State Handling

### 8.1 Migration Guardrails
`scripts/verify-migration.sh` executes during preflight:
1. Detects legacy Docker named volumes matching known suffixes (`nextcloud-db`, `nextcloud-data`, `onlyoffice-*`, `portainer-data`, `duplicati-config`, `adguard-*`, `stirling-*`, `netdata-*`).
2. Detects non-empty legacy bind paths (`$COMPANY_LEGACY_NEXTCLOUD_DATA_PATH`, default `/mnt/storage`).
3. If legacy data is detected, startup is blocked unless `$COMPANY_STORAGE_ROOT/.company-migration-complete` exists.
4. The receipt must:
   - Match `COMPANY_MIGRATION_RECEIPT_VERSION=1`.
   - List every detected volume as `MIGRATED_LEGACY_VOLUME=<name>`.
   - List the legacy path as `MIGRATED_LEGACY_PATH=<path>`.
5. All destination directories (`nextcloud/html`, `nextcloud/data`, `mariadb`, `onlyoffice/data`, `application-data`) must exist and contain at least one file.

### 8.2 Safe Cutover Workflow
1. Take an independent offline backup of legacy volumes and directories.
2. Mount approved storage pools and run `scripts/initialize-storage-layout.sh`.
3. Stop old containers.
4. Copy data preserving permissions (`chown -R www-data:www-data` for Nextcloud; `chown -R 999:999` for MariaDB).
5. Perform test database import and file verification.
6. Generate the migration receipt:
   ```bash
   sudo /opt/server/scripts/record-migration-complete.sh "reviewer-name"
   ```
7. Mark storage ready:
   ```bash
   sudo /opt/server/scripts/initialize-storage-layout.sh --mark-ready
   ```
8. Start the managed stack via `sudo systemctl start company-applications.service`.

---

## 9. Backup Architecture

### 9.1 Local Application-Consistent Database Backup
Automated daily by `systemd/company-mariadb-backup.timer` (executes `scripts/backup-mariadb.sh` at 01:30 UTC):
1. **Preflight:** Validates storage and backup mounts.
2. **Dump Pipeline:** Streams `mariadb-dump --single-transaction --routines --events` through `gzip -9` directly to a temporary file:
   `$COMPANY_BACKUP_ROOT/mariadb/nextcloud-TIMESTAMP.sql.gz.partial`
3. **Integrity Validation:**
   - Validates gzip format integrity: `gzip -t`.
   - Validates uncompressed content is non-empty and contains valid SQL headers:
     `gzip -dc "$temporary_file" | head -c 2048 | grep -Eq 'CREATE DATABASE|USE |MariaDB dump|Table structure'`.
4. **Manifest Creation:** Computes SHA-256 hash formatted with the final artifact basename:
   `<hash>  nextcloud-TIMESTAMP.sql.gz` written to `.partial.sha256`.
5. **Atomic Rename:** Atomically moves `.partial` and `.partial.sha256` to `.sql.gz` and `.sha256`.
6. **Error Trapping:** On any pipeline or validation error, the EXIT trap removes temporary files; no corrupt `.sql.gz` artifact is ever created.

### 9.2 Target 3-2-1-1-0 Offsite Backup Design
Production readiness requires completing the offsite backup pipeline:
1. **Local Copy 1:** Production dataset storage with snapshots.
2. **Local Copy 2:** Dedicated backup mount (`/mnt/company-backup/mariadb`).
3. **Offsite Copy:** Duplicati encrypted backup to a dedicated Backblaze B2 bucket.
4. **Immutability:** B2 Object Lock enabled with compliant retention period.
5. **Verification (0 Errors):** Recurring automated restoration drills into isolated environments.

---

## 10. Disaster Recovery and Failure Scenarios

| Scenario | Detection | Immediate Containment | Restoration Procedure | Target RPO / RTO |
|---|---|---|---|---|
| **Single Disk Failure** | SMART alert or ZFS pool degradation. | Verify redundancy; identify disk by physical serial/bay. | Off-line failed drive, insert replacement, initiate resilver: `zpool replace company <old> <new>`. Verify scrub. | RPO: 0<br>RTO: No downtime (resilver in background) |
| **Complete Server Loss** | Host hardware destruction or total outage. | Provision new hardware; attach storage or prepare recovery disks. | Deploy base OS via Ansible; restore `/opt/server/.env`; mount storage; restore latest Duplicati snapshot and MariaDB dump; run Nextcloud integrity check. | RPO: 24h (backup interval)<br>RTO: 4–8h |
| **OS Drive Corruption** | Host boot failure or kernel panic; storage array intact. | Boot recovery live environment; preserve storage arrays. | Reinstall base OS on new boot drive; run Ansible playbook; attach and import storage pools; start systemd lifecycle. | RPO: 0 (data pool intact)<br>RTO: 1–2h |
| **Database Corruption** | Nextcloud SQL errors or failed MariaDB start. | Stop applications: `systemctl stop company-applications`. Preserve corrupt datadir for forensics. | Select latest verified `nextcloud-*.sql.gz` and `.sha256`; verify checksum; restore dump into clean MariaDB; run `occ maintenance:repair`. | RPO: 24h<br>RTO: 1–2h |
| **Accidental File Deletion** | Employee report of lost files/folders. | Stop sync client to prevent propagation. | 1. Restore from Nextcloud trash bin / version history.<br>2. If purged, mount read-only ZFS snapshot and copy file back.<br>3. Restore from Duplicati if snapshot expired. | RPO: Snapshot interval (1h)<br>RTO: 15–30m |
| **Ransomware Outage** | Mass encrypted file extension alert or high pool write churn. | Disconnect infected endpoint from network. Stop Nextcloud: `systemctl stop company-applications`. | Identify pre-incident ZFS snapshot or immutable B2 backup; rollback or restore to clean state; rotate all user and system credentials. | RPO: Snapshot interval<br>RTO: 2–4h |
| **Backup Key Compromise** | Unauthorized B2 API access alert. | Revoke compromised B2 Application Key immediately via master credentials. | Lock bucket; verify Object Lock prevented unauthorized deletions; issue scoped new keys; update `/opt/server/.env`. | RPO: Current<br>RTO: 1h |

---

## 11. Security Architecture and Access Boundaries

### 11.1 Administrative Hardening
- **Tailscale Authentication:** SSH (22) and Admin Traefik (8443) are bound exclusively to the Tailscale private network.
- **Fail2ban:** Enabled with SSH jail (`bantime = 3600`, `maxretry = 5`).
- **Conditional SSH Hardening:** Password authentication and root login are disabled only after `company_tailscale_access_confirmed: true` is verified.
- **Docker Privilege Restrictions:**
  - Traefik and Portainer operate with `security_opt: [no-new-privileges:true]`.
  - Docker socket is mounted read-only (`:ro`) in Traefik, Portainer, and Netdata.
  - Stirling PDF enforces internal security authentication (`DOCKER_ENABLE_SECURITY=true`).

### 11.2 Secret Management
- Secrets are stored on the server host in `/opt/server/.env`, owned by `root:root` (mode `0600`).
- `.env` is explicitly ignored by Git (`.gitignore:2:.env`) and untracked.
- GitHub Actions workflows inject only SSH keys to trigger the deployment script; application secrets are never committed to GitHub or passed through CI environment logs.

---

## 12. Deployment Architecture

### 12.1 Serial Canary Rollout Workflow
Deployments are automated through GitHub Actions (`.github/workflows/deploy.yml`) on push to `main`:

```text
git push origin main
   │
   ▼
[Job 1: deploy-server-a]
   │
   ├─► SSH to Server A
   ├─► git fetch origin main
   ├─► TARGET_SHA=$(git rev-parse origin/main)
   ├─► git worktree add "$PREFLIGHT_TREE" "$TARGET_SHA"
   ├─► bash "$PREFLIGHT_TREE/scripts/production-preflight.sh"
   │     (If preflight fails, abort immediately; live checkout remains unmutated)
   ├─► git merge --ff-only "$TARGET_SHA" (Immutable commit deployment)
   ├─► sudo systemctl restart company-applications.service
   └─► sudo systemctl is-active --quiet company-applications.service
   │
   │ [Server A Deploy & Health Passed]
   ▼
[Job 2: deploy-server-b] (needs: deploy-server-a)
   │
   └─► Executes identical canary sequence on Server B
```

### 12.2 Immutable Commit Guarantee
The deployment workflow preflights the fetched revision in an isolated temporary worktree (`git worktree add --detach "$PREFLIGHT_TREE" "$TARGET_SHA"`). Only after preflight passes does `git merge --ff-only "$TARGET_SHA"` execute, ensuring that:
`THE COMMIT THAT PASSED PREFLIGHT = THE COMMIT THAT IS DEPLOYED`

---

## 13. Monitoring and Telemetry

### 13.1 Host and Container Telemetry (Netdata)
- Deployed via `services/netdata/docker-compose.yml`.
- Accessible exclusively via the private administrative port at `https://monitor.${DOMAIN}:8443`.
- Monitors host CPU, RAM, disk I/O, network bandwidth, container health, and swap utilization.

### 13.2 Recommended Storage Telemetry
Prior to production use, configure host-level alerts for:
- **ZFS Pool Health:** Alert on degraded state or read/write/checksum errors (`zpool status`).
- **SMART Health:** Automated daily short and monthly long tests via `smartd`. Alert on reallocated or pending sectors.
- **Capacity Thresholds:**
  - < 70%: Normal operating range.
  - 70%–80%: Warning (plan capacity expansion or snapshot pruning).
  - 80%–90%: High warning (investigate growth rate immediately).
  - \> 90%: Critical emergency (ZFS performance degradation and write failure risk).

---

## 14. Hardware Requirements and Sizing

### 14.1 Hardware Decision Record (Required Before Provisioning)

| Component | Specification / Requirement | Operational Justification |
|---|---|---|
| **Server Platform** | Enterprise 1U/2U rackmount (Dell PowerEdge, HPE ProLiant, Supermicro) with dedicated BMC/IPMI. | Out-of-band remote power cycling and console recovery during network/SSH lockout. |
| **CPU** | 8+ cores (x86_64, AMD EPYC or Intel Xeon). | Concurrent document rendering in ONLYOFFICE and background thumbnail processing. |
| **RAM** | 32 GB minimum; 64 GB+ recommended. ECC RAM strongly required. | ZFS ARC cache requirements and in-memory transactional consistency. |
| **Boot Storage** | 2× enterprise SSDs in hardware or OS mirror (separate from data pool). | Prevents host OS crash upon application data disk failure. |
| **Data Storage** | 2× to 6× enterprise SATA/SAS drives (CMR only; SMR prohibited). | Redundant pool structure (ZFS Mirror or RAIDZ2). |
| **Storage HBA** | Host Bus Adapter flashed to IT Mode (JBOD). Hardware RAID controllers prohibited for ZFS. | Allows ZFS direct control of disk communication and cache flush commands. |
| **Network** | 2× 1GbE minimum (bonded/failover) or 10GbE. | High-throughput file synchronization and local backup staging. |
| **UPS** | Smart UPS (APC, Eaton) with USB/Network management card. | Automated clean host shutdown via `apcupsd` or `nut` during sustained power loss. |

### 14.2 Storage Layout Recommendations

| Raw Drives | Layout | Usable Capacity | Fault Tolerance | Sizing Notes |
|---|---|---:|---:|---|
| **2 Drives** | 1× ZFS Mirror | 1× Drive Size | 1 Drive | Recommended baseline for small office (up to 25 users). Fast random I/O. |
| **4 Drives** | 2× ZFS Mirrors | 2× Drive Size | 1 Drive per mirror | Excellent database performance; rapid resilver times. |
| **4 Drives** | 1× RAIDZ2 | 2× Drive Size | 2 Drives | High redundancy; lower random write IOPS. |
| **6 Drives** | 1× RAIDZ2 | 4× Drive Size | 2 Drives | Optimal capacity and protection balance for bulk file storage (50–250 users). |

---

## 15. Administrator Runbook

### 15.1 Starting the Stack
```bash
# Verify storage and preflight manually:
sudo /opt/server/scripts/production-preflight.sh

# Start all applications:
sudo systemctl start company-applications.service

# Check service status:
sudo systemctl status company-applications.service
```

### 15.2 Stopping the Stack
```bash
# Gracefully stop applications in reverse dependency order:
sudo systemctl stop company-applications.service
```

### 15.3 Executing a Manual MariaDB Backup
```bash
sudo /opt/server/scripts/backup-mariadb.sh
```

### 15.4 Verifying a MariaDB Backup Checksum
```bash
cd /mnt/company-backup/mariadb
sha256sum -c nextcloud-TIMESTAMP.sql.gz.sha256
```

### 15.5 Restoring a MariaDB Database
```bash
# 1. Put Nextcloud into maintenance mode:
sudo /opt/server/scripts/compose-managed.sh nextcloud exec -T nextcloud occ maintenance:mode --on

# 2. Drop and recreate database:
sudo /opt/server/scripts/compose-managed.sh nextcloud exec -T nextcloud-db \
  mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -e "DROP DATABASE nextcloud; CREATE DATABASE nextcloud;"

# 3. Import verified backup:
zcat /mnt/company-backup/mariadb/nextcloud-TIMESTAMP.sql.gz | \
  sudo /opt/server/scripts/compose-managed.sh nextcloud exec -T nextcloud-db \
  mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" nextcloud

# 4. Run Nextcloud database migration checks:
sudo /opt/server/scripts/compose-managed.sh nextcloud exec -T nextcloud occ maintenance:repair

# 5. Disable maintenance mode:
sudo /opt/server/scripts/compose-managed.sh nextcloud exec -T nextcloud occ maintenance:mode --off
```

---

## 16. Production Readiness Checklist

Before promoting any host to live company production, verify:

- [ ] Hardware specification documented in [Section 14](#14-hardware-requirements-and-sizing).
- [ ] ZFS storage pool and backup pool provisioned with dedicated disks and ECC RAM.
- [ ] `/etc/company-storage.conf` created with exact `findmnt` facts matching the hardware pool.
- [ ] Directory layout created via `initialize-storage-layout.sh`.
- [ ] Historical data migrated and verified via `record-migration-complete.sh`.
- [ ] Readiness sentinel created via `initialize-storage-layout.sh --mark-ready`.
- [ ] Host `/opt/server/.env` configured with production secrets and restricted permissions (`0600`).
- [ ] Tailscale authenticated and `TAILSCALE_ADMIN_BIND_IP` assigned to `tailscale0`.
- [ ] Out-of-band console access verified before setting `company_tailscale_access_confirmed: true`.
- [ ] `production-preflight.sh` passes with zero warnings or errors.
- [ ] Systemd units enabled and tested across a full physical reboot.
- [ ] Automated MariaDB daily backup verified via `sha256sum -c`.
- [ ] Duplicati configured with encrypted Backblaze B2 destination and Object Lock.
- [ ] End-to-end bare-metal restoration drill executed and documented.

---

## 17. Live-Host Validation Checklist

The following tests **must** be executed on physical staging hardware:

### 17.1 Storage Tests
- [ ] Unmount `/mnt/company` and verify `systemctl start company-applications` fails immediately.
- [ ] Configure mismatched source or fstype in `company-storage.conf` and verify startup fails.
- [ ] Verify ZFS dataset compression (`zfs get compression company`).
- [ ] Verify automated monthly scrub timer (`zpool scrub company`).
- [ ] Simulate power pull and verify clean UPS shutdown.

### 17.2 Lifecycle Tests
- [ ] Execute `systemctl restart docker` and verify no stateful container starts automatically.
- [ ] Reboot server and verify `company-storage-guard.service` runs before `company-applications.service`.
- [ ] Verify all healthchecks in `check-services.sh` return exit 0 after reboot.

### 17.3 Network and Firewall Tests
- [ ] Run external port scan (nmap) from public internet: verify only ports 80 and 443 are open.
- [ ] Verify port 8443 is completely closed/filtered from public IPv4 and IPv6.
- [ ] Verify port 8443 is accessible and serves valid TLS over Tailscale.
- [ ] Verify AdGuard port 53 is unreachable from unauthorized public networks.

### 17.4 Disaster Recovery Drill
- [ ] Wipe secondary test server.
- [ ] Rebuild server from Git repository, `.env`, and latest B2 backup.
- [ ] Log in as test user, open existing ONLYOFFICE document, and verify edit persistence.
- [ ] Measure and record actual RPO and RTO in incident logs.

---

## 18. Known Operational Limitations

1. **Single Node Resilience:** The platform is a single-primary-node deployment per site. While redundant disks protect against drive loss, a motherboard or datacenter outage causes service downtime until failover or recovery is initiated.
2. **Watchtower Disabled:** Automatic container updates are intentionally disabled to protect database schema compatibility. Image updates require scheduled maintenance windows.
3. **Manual ONLYOFFICE Nextcloud Pairing:** Following initial deployment, ONLYOFFICE app installation and JWT secret entry in Nextcloud Settings is a manual administrative step.
4. **Local Host Secrets:** Application credentials reside in `/opt/server/.env`. Secure file permissions (`0600`) and host access controls are the primary boundary.

---

## 19. Future Architectural Roadmap

The following enhancements are architecturally compatible but deferred to future phases:
- **Centralized Identity & SSO (Phase 2):** Integration with Keycloak or corporate Entra ID via SAML 2.0 / OIDC with mandatory WebAuthn MFA.
- **Enterprise File Governance (Phase 2):** Nextcloud Group Folders, automated file retention policies, and upload virus scanning via ClamAV.
- **Warm Standby Disaster Recovery (Phase 3):** Automated ZFS snapshot replication (`syncoid` / `zrepl`) to a secondary warm standby site.
- **Centralized Observability (Phase 4):** Promtail/Loki log shipping and Prometheus/Grafana alerting dashboards.
