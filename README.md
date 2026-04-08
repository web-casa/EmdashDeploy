# EmdashDeploy

[![GHCR Builder](https://github.com/web-casa/EmdashDeploy/actions/workflows/publish-ghcr-builder.yml/badge.svg)](https://github.com/web-casa/EmdashDeploy/actions/workflows/publish-ghcr-builder.yml)
[![GHCR App](https://github.com/web-casa/EmdashDeploy/actions/workflows/publish-ghcr-app.yml/badge.svg)](https://github.com/web-casa/EmdashDeploy/actions/workflows/publish-ghcr-app.yml)
![License](https://img.shields.io/github/license/web-casa/EmdashDeploy)
![OS](https://img.shields.io/badge/OS-Debian%2012%2F13%20%7C%20Ubuntu%2022%2F24%20%7C%20EL%208%2F9%2F10-blue)
![Runtime](https://img.shields.io/badge/Runtime-Docker%20%7C%20Podman-2496ED)
![Stack](https://img.shields.io/badge/Stack-EmDash%20%2B%20Caddy%20%2B%20PostgreSQL%20%2F%20SQLite-2ea44f)

Interactive VPS installer and operations toolkit for EmDash with Docker/Podman, optional Caddy HTTPS, backup, restore, and health checks.

Languages: **English** | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [Português](./README.pt.md)

Versioning for this project follows the `HiEmdash` line:

- Git tag: `<emdash-version>-hi.<revision>`
- Examples: `0.2.0-hi.1`, `0.2.0-hi.2`, `0.2.0-hi.3`
- When upstream EmDash moves to a new base version, reset the revision:
  `0.3.0-hi.1`

## Quick Start

Run the bootstrap installer directly:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=en
```

Generate files only:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=en --write-only
```

Non-interactive install:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=en --non-interactive
```

Preferred bootstrap usage:

- `bootstrap.sh --lang=en`
- `bootstrap.sh --lang=ja`
- `bootstrap.sh --lang=ko`
- `bootstrap.sh --lang=es`
- `bootstrap.sh --lang=de`
- `bootstrap.sh --lang=fr`
- `bootstrap.sh --lang=zh-CN`
- `bootstrap.sh --lang=zh-TW`
- `bootstrap.sh --lang=pt`

Compatible bootstrap wrappers:

- `bootstrap.en.sh`
- `bootstrap.ja.sh`
- `bootstrap.ko.sh`
- `bootstrap.es.sh`
- `bootstrap.de.sh`
- `bootstrap.fr.sh`
- `bootstrap.zh-CN.sh`
- `bootstrap.zh-TW.sh`
- `bootstrap.pt.sh`

Available local installer wrappers:

- `install-emdash.en.sh`
- `install-emdash.ja.sh`
- `install-emdash.ko.sh`
- `install-emdash.es.sh`
- `install-emdash.de.sh`
- `install-emdash.fr.sh`
- `install-emdash.zh-CN.sh`
- `install-emdash.zh-TW.sh`
- `install-emdash.pt.sh`

CLI wrappers:

- `emdashctl.en.sh`
- `emdashctl.ja.sh`
- `emdashctl.ko.sh`
- `emdashctl.es.sh`
- `emdashctl.de.sh`
- `emdashctl.fr.sh`
- `emdashctl.zh-CN.sh`
- `emdashctl.zh-TW.sh`
- `emdashctl.pt.sh`

If you prefer a local checkout:

```bash
git clone https://github.com/web-casa/EmdashDeploy.git
cd EmdashDeploy
chmod +x bootstrap*.sh install-emdash*.sh emdashctl emdashctl*.sh linode-test.sh
sudo bash install-emdash.en.sh --activate
```

## What This Repository Does

This repository helps you install and operate [EmDash](https://github.com/emdash-cms/emdash) on a VPS.

It is designed for people who want:

- an interactive installer
- non-interactive installs with environment variables
- Docker on Debian/Ubuntu
- Podman on EL systems
- optional Caddy with automatic HTTPS
- backup, restore, health checks, and simple upgrade commands

It is not a generic PaaS. It is a focused deployment tool for EmDash.

## Features

- Interactive installer: [`install-emdash.sh`](./install-emdash.sh)
- Operations CLI: [`emdashctl`](./emdashctl)
- Real VPS smoke test helper: [`linode-test.sh`](./linode-test.sh)
- Optional native Caddy install on the host
- SQLite or PostgreSQL 18
- File-based sessions or Redis
- Local filesystem or S3-compatible object storage
- Multi-source public IP detection
- Generated layout under `/data/emdash`
- Generated config under `/etc/emdash`
- JSON output for `status`, `doctor`, and `smoke`

## Supported Platforms

| OS family | Versions | Container runtime |
| --- | --- | --- |
| Debian | 12, 13 | Docker |
| Ubuntu | 22.04, 24.04 | Docker |
| EL-like | 8, 9, 10 | Podman |

Notes:

- EL-like means Rocky Linux, AlmaLinux, RHEL-like variants, Oracle Linux, CentOS Stream, and similar systems handled by the installer.
- SLES family is not supported.
- Turso/libSQL is not supported.

## Non-Interactive Examples

SQLite with local storage:

```bash
EMDASH_INSTALL_DB_DRIVER=sqlite \
EMDASH_INSTALL_SESSION_DRIVER=file \
EMDASH_INSTALL_STORAGE_DRIVER=local \
sudo bash install-emdash.en.sh --non-interactive --activate
```

PostgreSQL with Redis:

```bash
EMDASH_INSTALL_DB_DRIVER=postgres \
EMDASH_INSTALL_PG_PASSWORD='change-me-now' \
EMDASH_INSTALL_SESSION_DRIVER=redis \
EMDASH_INSTALL_REDIS_PASSWORD='change-me-too' \
sudo bash install-emdash.en.sh --non-interactive --activate
```

## Main Commands

Installer:

```bash
sudo bash install-emdash.en.sh
sudo bash install-emdash.en.sh --activate
sudo bash install-emdash.en.sh --write-only
```

Operations:

```bash
emdashctl.en.sh status
emdashctl.en.sh status --json
emdashctl.en.sh doctor
emdashctl.en.sh doctor --json
emdashctl.en.sh smoke
emdashctl.en.sh smoke --json
emdashctl.en.sh logs app
emdashctl.en.sh restart app
emdashctl.en.sh backup
emdashctl.en.sh restore /path/to/backup.tar.gz
emdashctl.en.sh upgrade app
emdashctl.en.sh upgrade redis
emdashctl.en.sh upgrade caddy-config
emdashctl.en.sh reset-db-password
```

## Directory Layout

Default runtime paths:

- Root: `/data/emdash`
- Config: `/etc/emdash`
- CLI: `/usr/local/bin/emdashctl`

Common generated directories:

- `/data/emdash/app`
- `/data/emdash/compose`
- `/data/emdash/data`
- `/data/emdash/backups`
- `/data/emdash/logs`

## Caddy and HTTPS

If you enable Caddy, the installer will:

- detect public IPs from multiple providers
- validate DNS before continuing
- check port `80/443`
- install native Caddy on the host
- configure HTTPS

Firewall handling:

- On EL systems, the installer automatically opens `80/tcp` and `443/tcp` with `firewalld` when Caddy is enabled.
- On Debian/Ubuntu, the installer opens `80/tcp` and `443/tcp` if `ufw` is enabled.

## GHCR Publishing

This repository includes GitHub Actions workflows for publishing both the builder image and a default app image to GitHub Container Registry:

- Workflow: [`publish-ghcr-builder.yml`](./.github/workflows/publish-ghcr-builder.yml)
- Workflow: [`publish-ghcr-app.yml`](./.github/workflows/publish-ghcr-app.yml)
- Dockerfile: [`docker/base/Dockerfile`](./docker/base/Dockerfile)
- Published image: `ghcr.io/web-casa/emdash-builder:node24-bookworm`
- Published default app image: `ghcr.io/web-casa/emdash-app:starter-sqlite-file-local`
- Platform target: `linux/amd64,linux/arm64`

Builder vs app:

- `builder` is a reusable build environment image.
- `app` is a prebuilt runtime image.

Use `builder` when:

- you want the VPS to build the site locally
- you use PostgreSQL, Redis, or S3-compatible storage
- you changed the template or want full flexibility

Use `app` when:

- you want the fastest deployment path
- you want to skip local app builds on the VPS
- you are using the default published profile: `starter + sqlite + file + local`

The workflow runs when:

- `docker/base/Dockerfile` changes on `main`
- `.github/workflows/publish-ghcr-builder.yml` changes on `main`
- you trigger it manually with `workflow_dispatch`

The app image workflow runs when:

- `install-emdash.sh`, `lib/**`, or [`scripts/prepare-app-context.sh`](./scripts/prepare-app-context.sh) changes on `main`
- `.github/workflows/publish-ghcr-app.yml` changes on `main`
- you push a Git tag matching `*-hi.*`
- you trigger it manually with `workflow_dispatch`

Version-aware tags:

- Pushing Git tag `0.2.0-hi.3` will also publish:
  - `ghcr.io/web-casa/emdash-builder:0.2.0-hi.3`
  - `ghcr.io/web-casa/emdash-app:0.2.0-hi.3`
  - `ghcr.io/web-casa/emdash-app:starter-sqlite-file-local-0.2.0-hi.3`

How to use the published builder image:

```bash
EMDASH_INSTALL_APP_BASE_IMAGE=ghcr.io/web-casa/emdash-builder:node24-bookworm \
sudo bash install-emdash.en.sh --activate
```

How to use a prebuilt application image:

```bash
EMDASH_INSTALL_APP_IMAGE=ghcr.io/web-casa/emdash-app:starter-sqlite-file-local \
sudo bash install-emdash.en.sh --activate
```

Behavior:

- `APP_IMAGE` is pulled first
- if the pull succeeds, the installer starts the stack directly
- if the pull fails, the installer falls back to a local build

Recommendation:

- For general-purpose or customized deployments, prefer `APP_BASE_IMAGE`.
- For the default SQLite/file/local profile, prefer `APP_IMAGE`.

Important:

- If you want public unauthenticated pulls, set the GHCR package visibility to public.
- If you use a private image, authenticate the VPS host to `ghcr.io` before installation.
- The published default app image is intentionally limited to `starter + sqlite + file + local`, so it can be shared safely without baking external service secrets into the image.
- For PostgreSQL, Redis, or S3-backed deployments, prefer the builder image flow unless you intentionally want to publish a config-specific private app image.

## Real VPS Testing

Use [`linode-test.sh`](./linode-test.sh) to run a single direct VPS test against Linode.

1. Create a local `.env` file from the example:

```bash
cp .env.example .env
```

2. Add your token:

```bash
linode_token=YOUR_TOKEN_HERE
```

3. Run a test:

```bash
bash linode-test.sh
```

Run the predefined VPS matrix:

```bash
bash linode-test-matrix.sh
```

Run selected scenarios only:

```bash
bash linode-test-matrix.sh --scenario debian13-caddy-app,centos9-builder
```

HTTPS test with `sslip.io`:

```bash
LINODE_TEST_INSTALL_USE_CADDY=1 \
LINODE_TEST_INSTALL_ENABLE_HTTPS=1 \
LINODE_TEST_DOMAIN_PROVIDER=sslip.io \
bash linode-test.sh
```

HTTPS test with `nip.io`:

```bash
LINODE_TEST_INSTALL_USE_CADDY=1 \
LINODE_TEST_INSTALL_ENABLE_HTTPS=1 \
LINODE_TEST_DOMAIN_PROVIDER=nip.io \
bash linode-test.sh
```

Default test regions prefer the US:

```bash
LINODE_TEST_REGION_CANDIDATES=us-lax,us-west,us-east bash linode-test.sh
```

Matrix outputs:

- per-scenario JSON result files
- per-scenario failure logs
- one summary JSON
- one summary Markdown report

For the full scenario list and manual destructive checks, see [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md).

## Repository Layout

- [`install-emdash.sh`](./install-emdash.sh): main installer
- [`emdashctl`](./emdashctl): operations CLI
- [`linode-test.sh`](./linode-test.sh): real VPS test helper
- [`linode-test-matrix.sh`](./linode-test-matrix.sh): predefined VPS matrix runner
- [`lib/common.sh`](./lib/common.sh): shared helpers
- [`lib/config.sh`](./lib/config.sh): defaults and validation
- [`lib/os.sh`](./lib/os.sh): OS/runtime/package setup
- [`lib/prompt.sh`](./lib/prompt.sh): interactive prompts
- [`lib/network.sh`](./lib/network.sh): IP, DNS, and storage checks
- [`lib/render.sh`](./lib/render.sh): compose/Caddy/app rendering
- [`scripts/prepare-app-context.sh`](./scripts/prepare-app-context.sh): app image build context generator
- [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md): test matrix

## Current Limits

- No Turso/libSQL support
- No SLES family support
- `reset-db-password` supports PostgreSQL only
- `upgrade` supports `app`, `redis`, and `caddy-config`
- SQLite and Caddy use conservative tuning only
- The object storage preflight uses an AWS CLI container, so Docker or Podman must already be available
