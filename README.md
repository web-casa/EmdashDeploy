# EmdashDeploy

![License](https://img.shields.io/github/license/web-casa/EmdashDeploy)
![OS](https://img.shields.io/badge/OS-Debian%2013%20%7C%20Ubuntu%2024.04%20%7C%20EL%209%2F10-blue)
![Mode](https://img.shields.io/badge/Mode-Native%20Deployment-2ea44f)
![Stack](https://img.shields.io/badge/Stack-Node.js%20%2B%20Caddy%20%2B%20PostgreSQL%20%2F%20SQLite-2ea44f)

Native VPS installer and operations toolkit for EmDash with Node.js, systemd, optional Caddy HTTPS, backup, restore, and health checks.

Languages: **English** | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [Português](./README.pt.md)

Versioning for this project follows the `HiEmdash` line:

- Git tag: `<emdash-version>-hi.<revision>`
- Examples: `0.2.0-hi.1`, `0.2.0-hi.2`, `0.2.0-hi.3`
- When upstream EmDash moves to a new base version, reset the revision:
  `0.3.0-hi.1`

## Quick Start

Interactive install:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=en
```

Generate config only:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=en --write-only
```

Non-interactive install:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=en --non-interactive --activate
```

Local checkout:

```bash
git clone https://github.com/web-casa/EmdashDeploy.git
cd EmdashDeploy
chmod +x bootstrap.sh install.sh emdashctl linode-test.sh
sudo bash install.sh --lang=en --activate
```

Unified command style:

- `bootstrap.sh --lang=<code>`
- `install.sh --lang=<code>`
- `emdashctl --lang=<code>`

## What This Repository Does

This repository installs and operates [EmDash](https://github.com/emdash-cms/emdash) directly on a VPS.

It is designed for people who want:

- an interactive installer
- non-interactive installs with environment variables
- native Node.js deployment with `systemd`
- optional Caddy with automatic HTTPS
- SQLite or PostgreSQL 18
- file sessions or Redis
- local filesystem or S3-compatible object storage
- backup, restore, health checks, and straightforward upgrade commands

The container-based implementation has been archived to the `docker` branch. `main` is now native deployment only.

## Supported Platforms

| OS family | Versions | Notes |
| --- | --- | --- |
| Debian | 13 | Native install |
| Ubuntu | 24.04 | Native install |
| EL-like | 9, 10 | Native install |

Notes:

- EL-like means Rocky Linux, AlmaLinux, RHEL-like variants, Oracle Linux, CentOS Stream, and similar systems handled by the installer.
- Node.js is installed from `NodeSource`.
- PostgreSQL 18 is installed from `PGDG`.
- Redis uses the system package. On EL10 the installer automatically uses `valkey` when that is the packaged service.

## Features

- Interactive installer: [`install.sh`](./install.sh)
- Operations CLI: [`emdashctl`](./emdashctl)
- Real VPS smoke test helper: [`linode-test.sh`](./linode-test.sh)
- Native `systemd` service for the EmDash app
- Native Caddy install on the host
- SQLite or PostgreSQL 18
- File-based sessions or Redis
- Local filesystem or S3-compatible object storage
- S3-compatible backups
- JSON output for `status`, `doctor`, and `smoke`
- Multi-language installer and operator CLI
- Generated layout under `/data/emdash`
- Generated config under `/etc/emdash`

## Default Layout

Default runtime paths:

- Root: `/data/emdash`
- Site: `/data/emdash/app/site`
- Data: `/data/emdash/data`
- Backups: `/data/emdash/backups`
- Logs: `/data/emdash/logs`
- Config: `/etc/emdash`
- CLI: `/usr/local/bin/emdashctl`

Important generated files:

- `/etc/emdash/install.yml`
- `/etc/emdash/emdash.env`
- `/etc/systemd/system/emdash-app.service`
- `/data/emdash/app/emdash-build.sh`
- `/data/emdash/app/emdash-start.sh`

## Non-Interactive Examples

SQLite with local storage:

```bash
EMDASH_INSTALL_DB_DRIVER=sqlite \
EMDASH_INSTALL_SESSION_DRIVER=file \
EMDASH_INSTALL_STORAGE_DRIVER=local \
sudo bash install.sh --lang=en --non-interactive --activate
```

PostgreSQL with Redis:

```bash
EMDASH_INSTALL_DB_DRIVER=postgres \
EMDASH_INSTALL_PG_PASSWORD='change-me-now' \
EMDASH_INSTALL_SESSION_DRIVER=redis \
EMDASH_INSTALL_REDIS_PASSWORD='change-me-too' \
sudo bash install.sh --lang=en --non-interactive --activate
```

Caddy with HTTPS:

```bash
EMDASH_INSTALL_USE_CADDY=1 \
EMDASH_INSTALL_ENABLE_HTTPS=1 \
EMDASH_INSTALL_DOMAIN=example.com \
EMDASH_INSTALL_ADMIN_EMAIL=you@example.com \
sudo bash install.sh --lang=en --non-interactive --activate
```

S3-compatible media storage:

```bash
EMDASH_INSTALL_STORAGE_DRIVER=s3 \
EMDASH_INSTALL_S3_ENDPOINT='https://s3.example.com' \
EMDASH_INSTALL_S3_REGION='auto' \
EMDASH_INSTALL_S3_BUCKET='emdash-media' \
EMDASH_INSTALL_S3_ACCESS_KEY_ID='...' \
EMDASH_INSTALL_S3_SECRET_ACCESS_KEY='...' \
sudo bash install.sh --lang=en --non-interactive --activate
```

## Main Commands

Installer:

```bash
sudo bash install.sh --lang=en
sudo bash install.sh --lang=en --activate
sudo bash install.sh --lang=en --write-only
```

Operations:

```bash
emdashctl --lang=en status
emdashctl --lang=en status --json
emdashctl --lang=en doctor
emdashctl --lang=en doctor --json
emdashctl --lang=en smoke
emdashctl --lang=en smoke --json
emdashctl --lang=en logs app
emdashctl --lang=en restart app
emdashctl --lang=en backup
emdashctl --lang=en restore /path/to/backup.tar.gz
emdashctl --lang=en upgrade app
emdashctl --lang=en upgrade caddy-config
emdashctl --lang=en reset-db-password
```

## Upgrade Model

Native upgrades follow the host-side workflow:

1. refresh template source
2. sync the selected template into the live site tree
3. run `pnpm install`
4. run `pnpm build`
5. restart `emdash-app.service`

This is implemented by:

```bash
emdashctl --lang=en upgrade app
```

## Caddy and HTTPS

If you enable Caddy, the installer will:

- detect public IPs from multiple providers
- show the detected public IPv4 and IPv6
- ask you to finish DNS resolution before continuing
- validate DNS and port `80/443` before activation
- install native Caddy on the host
- configure HTTPS

Firewall handling:

- On EL systems, the installer automatically opens `80/tcp` and `443/tcp` with `firewalld` when Caddy is enabled.
- On Debian/Ubuntu, the installer opens `80/tcp` and `443/tcp` if `ufw` is enabled.

Without Caddy, the app binds directly to `0.0.0.0:${APP_PORT}` and the installer publishes a public `http://<server-ip>:3000` URL.

## Backup and Restore

Supported backup targets:

- `local`
- `s3`

What is included:

- install snapshot
- runtime env file
- SQLite database or PostgreSQL dump
- local uploads
- file sessions

For S3-compatible storage and backups, the native path now uses Python `boto3` rather than a containerized AWS CLI helper.

## Operator Examples

Restore the latest backup:

```bash
latest="$(ls -1 /data/emdash/backups/emdash-backup-*.tar.gz | tail -n1)"
emdashctl --lang=en restore "$latest"
```

Rotate the PostgreSQL password:

```bash
emdashctl --lang=en reset-db-password
```

Refresh the template, rebuild, and restart:

```bash
emdashctl --lang=en upgrade app
```

## Compatibility

Repository-level language alias files have been removed.

Current supported entrypoints:

- `bootstrap.sh --lang=<code>`
- `install.sh --lang=<code>`
- `emdashctl --lang=<code>`

During install or upgrade, the installer rewrites recognized system-level cron entries and systemd `Exec*` lines that still call the old `emdashctl.<lang>.sh` form, then removes stale alias files from `/usr/local/bin`.

Not migrated automatically:

- arbitrary user scripts
- user crontabs
- shell history
- bookmarked raw GitHub URLs for removed alias files

See [`COMPATIBILITY.md`](./COMPATIBILITY.md).

## Migration from `docker` Branch

If you were using the previous container-based implementation:

1. keep using the `docker` branch if you want Docker/Podman deployment
2. use `main` only for the native installer
3. expect a different runtime model:
   - no `compose.yml`
   - no container runtime requirement
   - app managed by `systemd`
   - services installed directly on the host
4. review native paths before migrating:
   - `/etc/emdash/emdash.env`
   - `/etc/systemd/system/emdash-app.service`
   - `/data/emdash/app/site`
5. if you migrate an existing host, take a fresh backup first

The archived container implementation remains on the `docker` branch.

## Known Limits

- `main` no longer provides Docker/Podman deployment
- supported systems are limited to Debian 13, Ubuntu 24.04, EL9, and EL10
- PostgreSQL password reset support is for native PostgreSQL installs only
- `upgrade` currently supports `app` and `caddy-config`
- user crontabs and arbitrary user scripts are not automatically rewritten during command-interface migration
- template, plugin, and build-time config changes still require `pnpm build`

## Tested Native Matrix

Real VPS verification on `main` currently includes:

- Debian 13 + SQLite + file
- Ubuntu 24.04 + SQLite + file
- EL9 + SQLite + Redis
- EL10 + SQLite + Redis
- EL9 + Caddy + HTTPS
- Debian 13 + Caddy + HTTPS
- Ubuntu 24.04 + Caddy + HTTPS
- Ubuntu 24.04 + PostgreSQL + file
- Ubuntu 24.04 + PostgreSQL + Redis + Caddy
- EL9 + PostgreSQL + Redis + Caddy
- EL10 + PostgreSQL + Redis + Caddy
- Debian 13 + S3-compatible media storage
- Ubuntu 24.04 + S3 backup

Detailed scenarios and operator checks are documented in [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md).

## Repository Guide

Key files:

- [`install.sh`](./install.sh): unified installer entry
- [`install-emdash.sh`](./install-emdash.sh): main native installer
- [`emdashctl`](./emdashctl): native operator CLI
- [`linode-test.sh`](./linode-test.sh): Linode real-VPS test helper
- [`lib/os.sh`](./lib/os.sh): OS packages, NodeSource, PGDG, Redis, Caddy
- [`lib/render.sh`](./lib/render.sh): native env, systemd, site rendering
- [`lib/network.sh`](./lib/network.sh): public IP detection and S3 checks

Historical container release material remains under `release-assets/` and the archived implementation remains on the `docker` branch.
