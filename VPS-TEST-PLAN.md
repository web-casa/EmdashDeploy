# VPS Test Plan

This document defines the native-deployment VPS regression plan for `main`.

The goal is to verify the current host-based installer and operator workflow on real machines, not just run shell syntax checks.

## Goals

- verify the real `install-emdash.sh` native install path
- verify `emdashctl` high-risk operational commands (`doctor --deep`, `diagnose`, `rotate-encryption-key`, `upgrade app`, `backup`/`restore`, `reset-db-password`)
- verify Debian 13, Ubuntu 24.04, Ubuntu 26.04 LTS, EL9, and EL10
- verify `SQLite`, `PostgreSQL 18`, `Valkey/Redis`, `Caddy + HTTPS`, `S3 storage`, and `S3 backup`
- verify that recently fixed native-only regressions stay closed

## Generic Remote Host E2E Script

For any SSH-reachable test VM (PVE, Hetzner, DigitalOcean, self-hosted KVM, etc.), use [`scripts/remote-e2e-verify.sh`](./scripts/remote-e2e-verify.sh):

```bash
# Safe read-only verification (default): status, doctor --deep, diagnose, upgrade --dry-run, template diff
bash scripts/remote-e2e-verify.sh --host root@<vm-ip>

# Full destructive lifecycle verification + reboot autostart check (use only on disposable test VMs)
bash scripts/remote-e2e-verify.sh --host root@<vm-ip> --destructive --verify-reboot --db postgres --session redis
```

Safety boundaries:
- Read-only by default; mutating operations require `--destructive`, and reboot testing requires `--verify-reboot`.
- Never uses `StrictHostKeyChecking=no`, never enables `set -x`, and transfers ephemeral test passwords via a `0600` remote env file instead of CLI arguments.

## Principles

- start with automated Linode smoke coverage
- keep destructive command tests on retained instances
- keep these artifacts for every round:
  - `emdashctl status --json`
  - `emdashctl doctor --json`
  - `emdashctl smoke --json`
  - failure logs
  - `journalctl -u emdash-app`
  - `journalctl -u caddy` when Caddy is enabled

## Prerequisites

1. Prepare `.env`

```bash
linode_token=...
```

2. For S3 storage or backup tests, prepare S3-compatible credentials in `.env`

3. Default region strategy:

```bash
export LINODE_TEST_REGION_CANDIDATES=us-lax,us-west,us-east
```

## Automated Smoke Coverage

### A1. Debian 13 + SQLite + file + local

```bash
LINODE_TEST_IMAGE=linode/debian13 \
LINODE_TEST_INSTALL_DB_DRIVER=sqlite \
LINODE_TEST_INSTALL_SESSION_DRIVER=file \
LINODE_TEST_INSTALL_STORAGE_DRIVER=local \
LINODE_TEST_INSTALL_USE_CADDY=0 \
bash linode-test.sh
```

Acceptance:

- native install completes
- `emdashctl smoke --json` passes
- public URL points to the server IP, not loopback

### A2. Ubuntu 24.04 + SQLite + file + local

```bash
LINODE_TEST_IMAGE=linode/ubuntu24.04 \
LINODE_TEST_INSTALL_DB_DRIVER=sqlite \
LINODE_TEST_INSTALL_SESSION_DRIVER=file \
LINODE_TEST_INSTALL_STORAGE_DRIVER=local \
LINODE_TEST_INSTALL_USE_CADDY=0 \
bash linode-test.sh
```

Acceptance:

- native install completes
- `emdashctl smoke --json` passes

### A3. EL9 + SQLite + Redis + local

```bash
LINODE_TEST_IMAGE=linode/centos-stream9 \
LINODE_TEST_INSTALL_DB_DRIVER=sqlite \
LINODE_TEST_INSTALL_SESSION_DRIVER=redis \
LINODE_TEST_INSTALL_REDIS_PASSWORD='Redis-Test-123:@Value' \
LINODE_TEST_INSTALL_STORAGE_DRIVER=local \
LINODE_TEST_INSTALL_USE_CADDY=0 \
bash linode-test.sh
```

Acceptance:

- native install completes
- Redis service is healthy
- `emdashctl doctor --json` reports `redis` as `ok`

### A4. EL10 + SQLite + Redis + local

```bash
LINODE_TEST_IMAGE=linode/almalinux10 \
LINODE_TEST_INSTALL_DB_DRIVER=sqlite \
LINODE_TEST_INSTALL_SESSION_DRIVER=redis \
LINODE_TEST_INSTALL_REDIS_PASSWORD='Redis-Test-123:@Value' \
LINODE_TEST_INSTALL_STORAGE_DRIVER=local \
LINODE_TEST_INSTALL_USE_CADDY=0 \
bash linode-test.sh
```

Acceptance:

- native install completes
- `valkey` or `redis` service path works correctly
- `emdashctl smoke --json` passes

### B1. Ubuntu 24.04 + PostgreSQL + file

```bash
LINODE_TEST_IMAGE=linode/ubuntu24.04 \
LINODE_TEST_INSTALL_DB_DRIVER=postgres \
LINODE_TEST_INSTALL_SESSION_DRIVER=file \
LINODE_TEST_INSTALL_PG_PASSWORD='Pg-Test-123_Complex@Value' \
bash linode-test.sh
```

Acceptance:

- PostgreSQL 18 install completes
- setup API is reachable
- `emdashctl doctor --json` reports PostgreSQL connectivity as healthy

### B2. Ubuntu 24.04 + PostgreSQL + Redis + Caddy

```bash
LINODE_TEST_IMAGE=linode/ubuntu24.04 \
LINODE_TEST_INSTALL_DB_DRIVER=postgres \
LINODE_TEST_INSTALL_SESSION_DRIVER=redis \
LINODE_TEST_INSTALL_PG_PASSWORD='Pg-Test-123_Complex@Value' \
LINODE_TEST_INSTALL_REDIS_PASSWORD='Redis-Test-123:@Value' \
LINODE_TEST_INSTALL_USE_CADDY=1 \
LINODE_TEST_INSTALL_ENABLE_HTTPS=1 \
LINODE_TEST_DOMAIN_PROVIDER=sslip.io \
bash linode-test.sh
```

Acceptance:

- PostgreSQL and Redis both work
- `https://<domain>/healthz` is healthy
- `emdashctl smoke --json` passes

### B3. EL9 + PostgreSQL + Redis + Caddy

```bash
LINODE_TEST_IMAGE=linode/centos-stream9 \
LINODE_TEST_INSTALL_DB_DRIVER=postgres \
LINODE_TEST_INSTALL_SESSION_DRIVER=redis \
LINODE_TEST_INSTALL_PG_PASSWORD='Pg-Test-123_Complex@Value' \
LINODE_TEST_INSTALL_REDIS_PASSWORD='Redis-Test-123:@Value' \
LINODE_TEST_INSTALL_USE_CADDY=1 \
LINODE_TEST_INSTALL_ENABLE_HTTPS=1 \
LINODE_TEST_DOMAIN_PROVIDER=nip.io \
bash linode-test.sh
```

Acceptance:

- native EL path completes
- `firewalld` opening works
- `tls cert` is `ok`

### B4. EL10 + PostgreSQL + Redis + Caddy

```bash
LINODE_TEST_IMAGE=linode/almalinux10 \
LINODE_TEST_INSTALL_DB_DRIVER=postgres \
LINODE_TEST_INSTALL_SESSION_DRIVER=redis \
LINODE_TEST_INSTALL_PG_PASSWORD='Pg-Test-123_Complex@Value' \
LINODE_TEST_INSTALL_REDIS_PASSWORD='Redis-Test-123:@Value' \
LINODE_TEST_INSTALL_USE_CADDY=1 \
LINODE_TEST_INSTALL_ENABLE_HTTPS=1 \
LINODE_TEST_DOMAIN_PROVIDER=nip.io \
bash linode-test.sh
```

Acceptance:

- native EL10 path completes
- Redis/Valkey service detection works
- `emdashctl smoke --json` passes

### C1. Debian 13 + Caddy + HTTPS

```bash
LINODE_TEST_IMAGE=linode/debian13 \
LINODE_TEST_INSTALL_USE_CADDY=1 \
LINODE_TEST_INSTALL_ENABLE_HTTPS=1 \
LINODE_TEST_DOMAIN_PROVIDER=sslip.io \
bash linode-test.sh
```

Acceptance:

- `https://<domain>/healthz` is healthy
- `emdashctl doctor --json` reports `tls cert` as `ok`

### C2. Ubuntu 24.04 + Caddy + HTTPS

```bash
LINODE_TEST_IMAGE=linode/ubuntu24.04 \
LINODE_TEST_INSTALL_USE_CADDY=1 \
LINODE_TEST_INSTALL_ENABLE_HTTPS=1 \
LINODE_TEST_DOMAIN_PROVIDER=sslip.io \
bash linode-test.sh
```

Acceptance:

- Caddy HTTPS path completes
- `status`, `doctor`, and `smoke` all pass

### D1. Debian 13 + S3-compatible media storage

```bash
LINODE_TEST_IMAGE=linode/debian13 \
LINODE_TEST_INSTALL_STORAGE_DRIVER=s3 \
LINODE_TEST_INSTALL_S3_PROVIDER=custom \
LINODE_TEST_INSTALL_S3_ENDPOINT="$S3_ENDPOINT" \
LINODE_TEST_INSTALL_S3_REGION="$S3_REGION" \
LINODE_TEST_INSTALL_S3_BUCKET="$S3_BUCKET" \
LINODE_TEST_INSTALL_S3_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
LINODE_TEST_INSTALL_S3_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
LINODE_TEST_INSTALL_S3_PUBLIC_URL="$S3_PUBLIC_URL" \
bash linode-test.sh
```

Acceptance:

- storage preflight passes
- app starts successfully with S3 storage configured
- `emdashctl doctor --json` passes

### D2. Ubuntu 24.04 + S3 backup

```bash
LINODE_TEST_IMAGE=linode/ubuntu24.04 \
LINODE_TEST_RUN_BACKUP=1 \
LINODE_TEST_INSTALL_BACKUP_TARGET=s3 \
LINODE_TEST_INSTALL_BACKUP_S3_ENDPOINT="$S3_ENDPOINT" \
LINODE_TEST_INSTALL_BACKUP_S3_REGION="$S3_REGION" \
LINODE_TEST_INSTALL_BACKUP_S3_BUCKET="$S3_BUCKET" \
LINODE_TEST_INSTALL_BACKUP_S3_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
LINODE_TEST_INSTALL_BACKUP_S3_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
LINODE_TEST_INSTALL_BACKUP_S3_PREFIX=backups \
bash linode-test.sh
```

Acceptance:

- `emdashctl backup` completes
- remote object upload completes
- `head_object` verification succeeds

## Retained-Instance Operator Tests

Use retained instances for commands that are destructive or require multi-step verification.

### E1. SQLite restore

```bash
LINODE_TEST_KEEP=1 \
LINODE_TEST_IMAGE=linode/debian13 \
LINODE_TEST_INSTALL_DB_DRIVER=sqlite \
LINODE_TEST_INSTALL_SESSION_DRIVER=file \
bash linode-test.sh
```

Remote commands:

```bash
emdashctl backup
latest="$(ls -1 /data/emdash/backups/emdash-backup-*.tar.gz | tail -n1)"
emdashctl restore "$latest"
emdashctl smoke --json
```

Acceptance:

- restore completes
- app becomes healthy again
- no stale `-wal/-shm` issue is visible

### E2. PostgreSQL restore

```bash
LINODE_TEST_KEEP=1 \
LINODE_TEST_IMAGE=linode/ubuntu24.04 \
LINODE_TEST_INSTALL_DB_DRIVER=postgres \
LINODE_TEST_INSTALL_SESSION_DRIVER=file \
LINODE_TEST_INSTALL_PG_PASSWORD='Pg-Test-123_Complex@Value' \
bash linode-test.sh
```

Remote commands:

```bash
emdashctl backup
latest="$(ls -1 /data/emdash/backups/emdash-backup-*.tar.gz | tail -n1)"
emdashctl restore "$latest"
emdashctl smoke --json
```

Acceptance:

- temporary database import works
- rename/switch completes
- app is healthy after restore

### E3. `upgrade app`

Use any retained native instance with a working site tree.

Remote commands:

```bash
emdashctl upgrade app
emdashctl status --json
emdashctl doctor --json
emdashctl smoke --json
```

Acceptance:

- template source refresh works
- `pnpm install` and `pnpm build` succeed
- app restarts healthy

### E4. `reset-db-password`

Use a retained PostgreSQL instance.

Remote commands:

```bash
emdashctl reset-db-password
emdashctl smoke --json
```

Acceptance:

- PostgreSQL role password is rotated
- environment is updated
- app reconnects and becomes healthy

### E5. Reboot and autostart

Use any retained instance.

Remote commands:

```bash
reboot
```

After SSH returns:

```bash
systemctl is-active emdash-app
emdashctl smoke --json
```

Acceptance:

- `emdash-app.service` starts automatically
- PostgreSQL, Redis, and Caddy dependencies recover correctly when enabled

## Phase F: Docker Compose Production Stack, Bidirectional Runtime Migration & Real S3 Loop (`1.6.0-hi.4+`)

### F1. Docker Compose PostgreSQL 18 + Valkey + Encrypted Backup / Atomic Restore

```bash
# Start prebuilt PG + Valkey image stack
docker compose -f docker/compose.yml --env-file docker/.env --profile postgres --profile valkey up -d
# Create encrypted custom-format PG backup (0600)
BACKUP_ENCRYPTION_PASSPHRASE='<passphrase>' bash docker/backup.sh --env-file docker/.env --encrypt
# Mutate PG data & delete uploads, then verify atomic temp-DB restore + swap
BACKUP_ENCRYPTION_PASSPHRASE='<passphrase>' bash docker/restore.sh <archive.tar.gz.enc> --env-file docker/.env --yes
```

Acceptance:

- `emdash`, `postgres`, and `valkey` containers all reach `healthy`
- `docker/backup.sh --encrypt` produces a `0600` archive passing `pg_restore --list`
- `docker/restore.sh --yes` restores into a temporary DB, atomically swaps via `ALTER DATABASE`, restores `/data/uploads`, and passes health checks

### F2. Docker Multi-Instance Coexistence + `compose.proxy-net.yml` Zero Host Ports

```bash
docker network create proxy
# Instance 1 on host loopback port
docker compose -p site-a -f docker/compose.yml --env-file site-a.env up -d
# Instance 2 attached to external proxy network with zero published host ports
docker compose -p site-b -f docker/compose.yml -f docker/compose.proxy-net.yml --env-file site-b.env up -d
```

Acceptance:

- `docker port <site-b-emdash-container>` is empty (no host port published)
- Both `site-a` (via loopback port) and `site-b` (via external Caddy/Nginx on `proxy` network) serve `/healthz` and `/_emdash/api/setup/status`

### F3. Custom Site Image Without `/healthz` (`Dockerfile.custom` + `compose.custom-site.yml`)

```bash
CUSTOM_SITE_DIR=/path/to/site-without-healthz \
  docker compose -f docker/compose.yml -f docker/compose.custom-site.yml --env-file custom.env up -d --build
BACKUP_ENCRYPTION_PASSPHRASE='<passphrase>' bash docker/backup.sh \
  --env-file custom.env --compose-file docker/compose.yml --compose-file docker/compose.custom-site.yml --encrypt
BACKUP_ENCRYPTION_PASSPHRASE='<passphrase>' bash docker/restore.sh <archive> \
  --env-file custom.env --compose-file docker/compose.yml --compose-file docker/compose.custom-site.yml --yes
```

Acceptance:

- `/healthz` returns `404`, yet container healthcheck reaches `healthy` via `/_emdash/api/setup/status`
- Repeatable `--compose-file` overlays work for both `docker/backup.sh` and `docker/restore.sh`

### F4. Bidirectional Runtime Migration (`docker-to-native` & `native-to-docker --apply`)

```bash
# Docker -> Native (preserving EMDASH_ENCRYPTION_KEY and caller BACKUP_ENCRYPTION_PASSPHRASE)
BACKUP_ENCRYPTION_PASSPHRASE='<docker-pass>' bash scripts/migrate-runtime.sh docker-to-native \
  --backup <docker-backup.tar.gz.enc> --docker-env <docker/.env> [--instance <name>] --yes

# Native -> Docker (extracting meta/+data/ cleanly, waiting for PG readiness, starting Valkey)
BACKUP_ENCRYPTION_PASSPHRASE='<native-pass>' DOCKER_APP_PORT=13000 \
  bash scripts/migrate-runtime.sh native-to-docker \
  --backup <native-backup.tar.gz.enc> --out-dir /tmp/emdash-docker-migrated --apply --yes
```

Acceptance:

- Both directions complete cleanly with distinct backup passphrases and preserve `EMDASH_ENCRYPTION_KEY` verbatim
- Seeded PostgreSQL rows (`$emdash` encrypted envelopes) and `/data/uploads` files survive both migrations intact
- Native `emdashctl doctor --deep` / `smoke` and Docker Compose container healthchecks all pass

### F5. Real S3-Compatible Storage, Remote Retention Pruning & Disaster Restore

Use an ephemeral local S3-compatible server (e.g., VersityGW or MinIO container) or a dedicated R2/S3 test bucket:

```bash
# Install named instance with STORAGE_DRIVER=s3 and BACKUP_TARGET=s3
bash install.sh --non-interactive --activate --instance s3-test
# Set BACKUP_KEEP_S3=2, run 3 encrypted backups, verify remote count == 2
emdashctl --instance s3-test backup --encrypt
emdashctl --instance s3-test backup --list-s3 --json
# Wipe local SQLite/PG data and local backup archives, then restore from S3
emdashctl --instance s3-test restore --from-s3 latest --yes
emdashctl --instance s3-test smoke --json
```

Acceptance:

- Installer S3 preflight (`put_object` + `delete_object`) and `doctor --deep` `s3 storage` check pass
- `BACKUP_KEEP_S3=2` prunes the oldest remote archive without polluting stdout backup path output
- `restore --from-s3 latest --yes` recovers the latest canary state after full local data loss

## Phase G: Cross-Distro Python 3.9, Legacy Caddy Migration, Multi-Instance Reboot & Chaos Guardrails (`1.6.0-hi.5+`)

### G1. Rocky Linux 9.9 (Python 3.9 + SELinux Enforcing) Zero-Downtime Upgrade & `migrate-db`

```bash
# Record MainPID before zero-downtime CLI refresh
systemctl show -p MainPID --value emdash-app
bash install.sh --update-cli
emdashctl instances --json
# Migrate a SQLite instance to PostgreSQL 18 on Python 3.9
EMDASH_TARGET_PG_PASSWORD='<pg-pass>' emdashctl --instance site2 migrate-db sqlite-to-postgres \
  --pg-db emdash_site2 --pg-user emdash_site2 --yes
emdashctl --instance site2 doctor --deep --json
```

Acceptance:

- `emdash-app` `MainPID` is unchanged after `--update-cli`
- `emdashctl instances` and `lib/migrate-sqlite-to-pg.py` execute cleanly on Python 3.9 without syntax/tarfile errors
- Dynamic `ec_*` tables and `$emdash` encrypted rows migrate intact (`missing_in_pg: []`) with `doctor --deep` all green under SELinux `Enforcing`

### G2. Legacy Pre-`1.6.0-hi.3` Single-File Caddyfile Auto-Migration & Safe Uninstall

```bash
# With legacy single-file /etc/emdash/caddy/Caddyfile + user /etc/emdash/caddy/conf.d/custom.caddy present:
bash install.sh --non-interactive --activate --instance site2
# Verify default, site2, and custom conf.d vhosts all serve HTTP concurrently
# Then uninstall site2 and verify Caddy reloads (stays active) without dropping default or conf.d
emdashctl --instance site2 uninstall --purge-data --drop-db --confirm-instance site2 --yes
systemctl is-active caddy
```

Acceptance:

- Legacy `{ email ... }` extracted into `/etc/emdash/caddy/global.email` and primary block migrated into `/etc/emdash/caddy/sites.d/default.caddy`
- User `/etc/emdash/caddy/conf.d/*.caddy` untouched across install and uninstall
- Uninstalling `site2` reloads Caddy (keeps it `active`) and preserves `/usr/local/bin/emdashctl` while sibling instances remain

### G3. `emdashctl upgrade app` User Code Preservation

```bash
# Add a custom Astro route under /data/emdash-site2/app/site/src/pages/user-owned.ts
emdashctl --instance site2 template diff --stat
emdashctl --instance site2 upgrade app --dry-run
emdashctl --instance site2 upgrade app
```

Acceptance:

- Custom user route survives `upgrade app` and serves live HTTP 200 after rebuild

### G4. 3-Instance Mixed Stack + Reboot Autostart & Per-Instance `flock` Concurrency

```bash
# Host running default (PG+Valkey :3000), site2 (SQLite+Caddy :3001), site3 (isolated PG DB/user + Valkey REDIS_DB=1 :3002)
# Parallel cross-instance backups must NOT block each other; same-instance lock contention must reject cleanly
reboot
# After SSH returns:
systemctl is-active emdash-app emdash-app-site2 emdash-app-site3 caddy postgresql-18 valkey
emdashctl instances
```

Acceptance:

- All 6 services auto-start cleanly after reboot under SELinux `Enforcing`
- Parallel `default` + `site2` backups succeed simultaneously; holding `/run/lock/emdashctl-site2.lock` rejects concurrent `site2` operations cleanly

### G5. Migration Failure Rollback & Destructive Uninstall Guardrails

```bash
# Non-empty target PG without --truncate-target -> must refuse
# Wrong PG password -> must refuse before mutating SQLite
# Mid-migration non-empty unmapped SQLite table -> must hard-fail and auto-rollback to SQLite
# uninstall --purge-data --yes without/wrong --confirm-instance -> must refuse
# uninstall --yes (without --purge-data) -> must preserve /data/emdash-<name>
```

Acceptance:

- Every negative guardrail exits non-zero and leaves the source instance untouched and healthy
- Non-purge `uninstall` removes systemd/cron/config while preserving `/data/emdash-<name>`

## Failure Collection

For every failed run, capture:

- `emdashctl status --json`
- `emdashctl doctor --json`
- `journalctl -u emdash-app -n 200 --no-pager`
- `journalctl -u caddy -n 200 --no-pager` when applicable
- `systemctl status postgresql* redis* valkey* caddy emdash-app --no-pager`

## Current Release-Prep Focus

Before cutting the next native release, confirm:

- Debian 13, Ubuntu 24.04, EL9, and EL10 all pass native smoke installs
- HTTPS is green on Debian, Ubuntu, and EL
- S3 storage and S3 backup both pass against the configured endpoint
- `upgrade app`, `restore`, and reboot/autostart are verified on real VPSes
