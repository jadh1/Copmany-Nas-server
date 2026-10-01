# ONLYOFFICE — Setup & Nextcloud Integration

## What It Does
ONLYOFFICE Document Server enables real-time co-editing of:
- Word documents (.docx)
- Excel spreadsheets (.xlsx)
- PowerPoint presentations (.pptx)

Multiple employees can edit the same file simultaneously — like Google Docs, but on company servers.

---

## Step 1 — Generate JWT Secret
Run this on your PC or server:
```bash
openssl rand -hex 32
```
Copy the output → paste into `.env` as `ONLYOFFICE_JWT_SECRET`

---

## Step 2 — Start ONLYOFFICE

### Production
In production, ONLYOFFICE is started via the managed systemd lifecycle:
```bash
# Start as part of the managed application stack:
sudo systemctl start company-applications.service

# Or start individually using the managed wrapper:
sudo /opt/server/scripts/compose-managed.sh onlyoffice up -d
```

### Local Development
For local testing using the development compose definition:
```bash
docker compose -f docker-compose.local.yml up -d onlyoffice
```

Wait 2-3 minutes for ONLYOFFICE Document Server to fully initialize.

---

## Step 3 — Connect Nextcloud to ONLYOFFICE

1. Open `https://files.company.com`
2. Login as Super Admin
3. Go to **Apps** → search **ONLYOFFICE** → Install
4. Go to **Settings** → **ONLYOFFICE**
5. Fill in:
   - Document Editing Service address: `https://office.company.com`
   - Secret key (JWT): same value as `ONLYOFFICE_JWT_SECRET` in `.env`
6. Click **Save** → green checkmark = working ✅

---

## How Employees Use It
- Open any .docx / .xlsx / .pptx file in Nextcloud
- It opens automatically in ONLYOFFICE in the browser
- Multiple users can open and edit simultaneously
- Changes save automatically back to Nextcloud

---

## Troubleshooting

**Red error on ONLYOFFICE settings page:**
- Make sure `office.company.com` is accessible
- Check JWT secret matches exactly in both `.env` and Nextcloud settings
- Check ONLYOFFICE container is running: `docker ps | grep onlyoffice`

**Files open but show blank:**
- Wait 2-3 minutes after starting container — ONLYOFFICE needs time to init
- Check logs: `docker logs onlyoffice --tail 50`
