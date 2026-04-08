# VPS Test Plan

This document defines the native-deployment VPS regression plan for `main`.

The goal is to verify the current host-based installer and operator workflow on real machines, not just run shell syntax checks.

## Goals

- verify the real `install-emdash.sh` native install path
- verify `emdashctl` high-risk operational commands
- verify Debian 13, Ubuntu 24.04, EL9, and EL10
- verify `SQLite`, `PostgreSQL`, `Redis`, `Caddy + HTTPS`, `S3 storage`, and `S3 backup`
- verify that recently fixed native-only regressions stay closed

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
