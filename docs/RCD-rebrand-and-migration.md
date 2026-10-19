# RCD ERP branding and migration

## Apply the RCD branding

The logo is baked into the custom image at both `/assets/frappe/images/rcd_logo.svg` and `/assets/erpnext/images/erpnext-logo.svg` (the ERPNext URL remains unchanged). Build the image before starting the stack:

```powershell
docker build -f Dockerfile.mobile-control -t erpnext-custom:v16.50.0 .
docker compose --env-file .env -f pwd.yml up -d --force-recreate
```

Once the site is up, set its branding and browser tab favicon in the database. These commands only update branding fields; they do not change API routes or service configuration:

```powershell
docker compose --env-file .env -f pwd.yml exec -T backend bench --site frontend execute frappe.db.set_single_value --args "['System Settings', 'app_name', 'RCD ERP']"
docker compose --env-file .env -f pwd.yml exec -T backend bench --site frontend execute frappe.db.set_single_value --args "['Website Settings', 'app_name', 'RCD ERP']"
docker compose --env-file .env -f pwd.yml exec -T backend bench --site frontend execute frappe.db.set_single_value --args "['Website Settings', 'app_logo', '/assets/frappe/images/rcd_logo.svg']"
docker compose --env-file .env -f pwd.yml exec -T backend bench --site frontend execute frappe.db.set_single_value --args "['Website Settings', 'favicon', '/assets/frappe/images/rcd_logo.svg']"
docker compose --env-file .env -f pwd.yml exec -T backend bench --site frontend execute frappe.db.set_single_value --args "['Navbar Settings', 'app_logo', '/assets/frappe/images/rcd_logo.svg']"
docker compose --env-file .env -f pwd.yml exec -T backend bench --site frontend execute frappe.clear_cache
```

The database settings survive container recreation. Rebuild the custom image on a new host (or transfer it with `docker save`) so the logo asset is present there too.

## Back up and move the site to Linux

Use a maintenance window so no one changes records during the final backup. These instructions back up the site's database and uploaded files, preserve the site configuration, and transfer the exact custom image and Compose configuration. Keep `.env` and `site_config.json` private: they contain credentials and encryption keys.

### 1. Make a portable backup on Windows

From this directory in PowerShell:

```powershell
$backup = Join-Path $PWD 'migration-backup'
New-Item -ItemType Directory -Force -Path $backup | Out-Null
docker compose --env-file .env -f pwd.yml stop frontend queue-long queue-short scheduler websocket
docker compose --env-file .env -f pwd.yml exec -T backend bench --site frontend backup --with-files
docker compose --env-file .env -f pwd.yml stop backend
$backend = docker compose --env-file .env -f pwd.yml ps -aq backend
docker cp "${backend}:/home/frappe/frappe-bench/sites/frontend/private/backups" (Join-Path $backup 'backups')
docker cp "${backend}:/home/frappe/frappe-bench/sites/frontend/site_config.json" (Join-Path $backup 'site_config.json')
docker cp "${backend}:/home/frappe/frappe-bench/sites/common_site_config.json" (Join-Path $backup 'common_site_config.json')
docker save -o (Join-Path $backup 'erpnext-custom-v16.50.0.tar') erpnext-custom:v16.50.0
Copy-Item .env, pwd.yml, Dockerfile.mobile-control, apps.json, app.json -Destination $backup
Copy-Item -Recurse branding -Destination $backup
```

Confirm the backup directory contains a database `.sql.gz`, public and private file archives, both site config files, the image archive, and the deployment files. Copy the whole `migration-backup` directory to the Linux machine using a secure transfer method. Name the deployment directory `frappe_docker` on Linux (or adjust the Compose project name and volume name consistently).

### 2. Restore on Linux

Install Docker Engine and the Docker Compose plugin. Use the transferred `migration-backup` directory as the deployment directory, named `frappe_docker`, then run the following from that directory. Restore the exact image tag before starting Compose so it will not pull or substitute a different image:

```bash
docker load -i erpnext-custom-v16.50.0.tar
docker compose --env-file .env -f pwd.yml up -d
```

Wait for the `frontend` site to be created and the services to become healthy. Copy `site_config.json`, `common_site_config.json`, and the backup archives into the matching paths inside the `sites` volume. One way to copy them is with a temporary helper container; first create the volume by starting Compose, then run from the deployment directory:

```bash
docker run --rm \
  -v frappe_docker_sites:/sites \
  -v "$PWD:/backup:ro" \
  alpine sh -ec '
    mkdir -p /sites/frontend/private/backups
    cp /backup/site_config.json /sites/frontend/site_config.json
    cp /backup/common_site_config.json /sites/common_site_config.json
    cp /backup/backups/* /sites/frontend/private/backups/
  '
```

Compose volume names are prefixed by the Compose project name. With the directory named `frappe_docker`, the sites volume is `frappe_docker_sites`; if you use another project name, find the actual volume with `docker volume ls` and replace it above. Restart the stack so the site config is read, then restore the database and both file archives (use the exact archive filenames from the backup):

```bash
docker compose --env-file .env -f pwd.yml restart backend frontend queue-long queue-short scheduler websocket
docker compose --env-file .env -f pwd.yml exec backend bench --site frontend restore /home/frappe/frappe-bench/sites/frontend/private/backups/<database-backup>.sql.gz \
  --with-public-files /home/frappe/frappe-bench/sites/frontend/private/backups/<public-files-backup>.tar \
  --with-private-files /home/frappe/frappe-bench/sites/frontend/private/backups/<private-files-backup>.tar \
  --db-root-username root --db-root-password admin
docker compose --env-file .env -f pwd.yml exec backend bench --site frontend migrate
```

Use `.tgz` instead of `.tar` in the restore paths when that is the archive extension produced by your backup. Confirm login, uploaded files, background jobs, and the API from the Linux host before switching users over. Keep the Windows server and backup untouched until that verification is complete.

### 3. Protect and retain backups

Store at least one additional encrypted copy off the server. Retain the matching deployment files and image with each backup, and do a test restore periodically. A `bench backup --with-files` backup is portable across hosts; copying only the database or only Docker volumes is not sufficient for a complete site restore.
