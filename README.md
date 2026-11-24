# EmdashDeploy

[![Release](https://img.shields.io/github/v/release/web-casa/EmdashDeploy?label=Release)](https://github.com/web-casa/EmdashDeploy/releases)
[![CI](https://github.com/web-casa/EmdashDeploy/actions/workflows/ci.yml/badge.svg)](https://github.com/web-casa/EmdashDeploy/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/web-casa/EmdashDeploy)](./LICENSE)
[![OS](https://img.shields.io/badge/OS-Debian%2013%20%7C%20Ubuntu%2024.04%2F26.04%20%7C%20EL%209%2F10-blue)](#supported-platforms--verified-matrix)
[![Arch](https://img.shields.io/badge/Arch-x86__64%20%7C%20ARM64-blue)](#supported-platforms--verified-matrix)
[![Mode](https://img.shields.io/badge/Mode-Native%20systemd%20%2B%20Docker%20Compose-2ea44f)](#choose-your-deployment-mode)

Production-ready **native VPS installer**, **operations CLI (`emdashctl`)**, and **coexistence-first multi-arch Docker Compose kit** for [EmDash](https://github.com/emdash-cms/emdash) `1.6.x`.

**Languages**: **English** | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [Português](./README.pt.md)

---

## Choose Your Deployment Mode

Both modes live on `main` and share the exact same EmDash `1.6.x` config patcher ([`lib/site-common.sh`](./lib/site-common.sh) & [`lib/astro-patch.py`](./lib/astro-patch.py)), plugin sandbox support (`@emdash-cms/sandbox-workerd`), encryption key validation, and migration safety rules.

| Dimension | Native VPS Installer (`install.sh` + `emdashctl`) | Docker Compose Kit ([`docker/`](./docker/README.md)) |
| --- | --- | --- |
| **Best for** | Dedicated VPS, lowest RAM overhead, direct `systemd` + host Caddy | Shared VPS alongside Nginx/Traefik/1Panel/other containers |
| **Runtime** | Host Node.js 24, `systemd`, Caddy, SQLite / PostgreSQL 18, Valkey | Prebuilt multi-arch GHCR images (`linux/amd64` + `linux/arm64`) |
| **Host ports** | Optional host Caddy (`80/443`) or direct `APP_PORT` | Does **not** bind `80/443` by default (`127.0.0.1:3000` only) |
| **Multi-site on 1 host** | Native `--instance <name>` + modular `/etc/emdash/caddy/sites.d/` | Separate `COMPOSE_PROJECT_NAME` + `APP_PORT` (or `compose.proxy-net.yml`) |
| **Custom / AI-modified site** | Preserves user code in `/data/emdash/app/site` (`preserve` mode) | Immutable build via [`docker/Dockerfile.custom`](./docker/Dockerfile.custom) |
| **Backup & Restore** | `emdashctl backup/restore` (local + S3 retention/list/restore) | [`docker/backup.sh`](./docker/backup.sh) + [`docker/restore.sh`](./docker/restore.sh) |
| **Cross-mode migration** | [`scripts/migrate-runtime.sh`](./scripts/migrate-runtime.sh) (`native-to-docker` ↔ `docker-to-native`) | Same |

> Looking for the archived legacy bash container installer? It remains preserved on the `docker` branch.

---

## Quick Start

### Option 1: Native VPS Install (Interactive)

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=en
```

Non-interactive SQLite + Caddy HTTPS install:

```bash
EMDASH_INSTALL_USE_CADDY=1 \
EMDASH_INSTALL_ENABLE_HTTPS=1 \
EMDASH_INSTALL_DOMAIN=blog.example.com \
EMDASH_INSTALL_ADMIN_EMAIL=ops@example.com \
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh \
  | sudo -E bash -s -- --lang=en --non-interactive --activate
```

Mainland China accelerated install (uses `npmmirror` for Corepack & `pnpm 11` + automatic Google Fonts build-time fast-fail, without mutating host APT/DNF repos):

```bash
EMDASH_MIRROR_PRESET=cn \
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh \
  | sudo -E bash -s -- --lang=zh-CN --non-interactive --activate
```

Install a second isolated native site on the same server:

```bash
sudo bash install.sh --lang=en --instance site2 --activate
```

Update `emdashctl` and shared libraries on an existing host with **zero downtime** (no rebuild or restart):

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --update-cli
```

### Option 2: Docker Compose Kit (Prebuilt Multi-Arch GHCR)

```bash
git clone https://github.com/web-casa/EmdashDeploy.git && cd EmdashDeploy/docker
cp .env.example .env
# Edit .env: set EMDASH_SITE_URL=https://blog.example.com and APP_PORT=3001
docker compose run --rm emdash secrets-generate
# Paste the generated key into EMDASH_ENCRYPTION_KEY in .env, then start:
docker compose up -d
```

For PostgreSQL 18 + Valkey 8 profiles, local China mirror builds (`compose.build.yml`), custom site repos (`compose.custom-site.yml`), external proxy networks (`compose.proxy-net.yml`), and container backup/restore, see [`docker/README.md`](./docker/README.md).

---

## Key Features (`1.6.0-hi.5`)

- **Full EmDash `1.6.x` Native Support**:
  - `EMDASH_ENCRYPTION_KEY` generation via `emdash secrets generate`, format/fingerprint verification, and safe **two-stage key rotation** (`emdashctl rotate-encryption-key`) with database encrypted-envelope `kid` scanning before pruning legacy keys.
  - `@emdash-cms/sandbox-workerd` + `workerd` plugin isolation enabled by default (configurable via `EMDASH_INSTALL_ENABLE_PLUGIN_SANDBOX`).
  - Explicit `emdash migrate --status --json` / `--expected-target-fingerprint` migration gate.
  - Reliable WebAuthn / Passkey origin propagation (`APP_PUBLIC_URL`, `EMDASH_SITE_URL`, `SITE_URL`).
- **Native Multi-Instance & Modular Caddy**:
  - Default single-instance paths (`/etc/emdash`, `/data/emdash`, `emdash-app.service`, port `3000`) stay 100% backward-compatible.
  - Named instances (`--instance <name>`) are fully isolated (`/etc/emdash/instances/<name>`, `/data/emdash-<name>`, `emdash-app-<name>.service`, `/etc/cron.d/emdash-backup-<name>`, auto-allocated free `APP_PORT` starting at `3001`, isolated `HOME=${ROOT_DIR}`, independent `flock`, and `emdash_<name>` PostgreSQL DB/role).
  - Modular `/etc/emdash/caddy/Caddyfile` with a single global `email` block, managed `sites.d/*.caddy`, and user-owned `conf.d/*.caddy` preserved across upgrades and uninstalls (legacy single-file Caddyfiles are automatically migrated on multi-instance expansion).
- **Non-Destructive Upgrades & Template Diff**:
  - `emdashctl upgrade app` updates only `emdash` / `@emdash-cms/*` dependencies, runs an exclusive `flock`, creates a verified pre-upgrade backup, builds, enforces the explicit migration gate, and preserves all custom pages, themes, styles, and `astro.config.mjs`.
  - `emdashctl template diff [--stat]` inspects upstream template changes read-only without touching your site.
- **AI-Friendly Redacted Diagnostics**:
  - `emdashctl diagnose --json [--out <file>]` (`schema_version: 1`) bundles host metadata, non-secret config summary (`encryption_key_kids`), `doctor --deep` (including upstream SQLite `emdash doctor` aggregation), migration status, service states, bounded `journalctl -o json` logs, and `suggested_next_steps`.
  - Recursively redacts passwords, DB/Redis URLs, `emdash_enc_v1_*`, Bearer/Basic auth headers, cookies, JWTs, sensitive query parameters, and client IPs (`--out` rejects symlinks and writes atomically with `0600`).
- **Complete Backup, S3 Retention & Restore Loop**:
  - Consistent SQLite `sqlite3.backup()` + `PRAGMA integrity_check`, PostgreSQL `pg_dump -Fc` + `pg_restore --list`, `manifest.json` + SHA-256 checksums, `0600` permissions, and AES-256-CBC PBKDF2 encryption (`--encrypt`).
  - Remote S3 retention pruning (`BACKUP_KEEP_S3`, default `14`, strictly matching managed backup filenames), `backup --list-s3 [--json]`, and one-command `restore --from-s3 <key|latest>`.
- **Database & Runtime Migration Assistants**:
  - `emdashctl migrate-db sqlite-to-postgres`: zero-dependency Python migrator ([`lib/migrate-sqlite-to-pg.py`](./lib/migrate-sqlite-to-pg.py)) with non-superuser FK topological sort, PG column type coercion (preserving `$emdash` encrypted envelopes verbatim), SQLite FTS5 shadow-table skipping, automatic PG DDL provisioning for dynamic `ec_*` collection tables (`ec_posts`, `ec_pages`, etc.), sequence resets, exact per-table row-count verification, and automatic rollback on failure.
  - [`scripts/migrate-runtime.sh`](./scripts/migrate-runtime.sh): `native-to-docker` and `docker-to-native` migration preserving `EMDASH_ENCRYPTION_KEY` with `0600` `.env` output.
- **Mainland China Build Acceleration**:
  - `EMDASH_MIRROR_PRESET=cn` sets `npmmirror` for Corepack & `pnpm 11` (both `NPM_CONFIG_REGISTRY` and lowercase `npm_config_registry` + `--registry=`) and enables [`lib/fast-fail-google-fonts.mjs`](./lib/fast-fail-google-fonts.mjs) when no proxy is configured, cutting Astro build times from ~120s font timeouts down to **~16–19s**.
- **Safe Uninstaller**:
  - `emdashctl uninstall` cleanly removes systemd unit, backup cron, Caddy snippet, and instance config while protecting sibling instances and `conf.d/*.caddy`. Destructive `--purge-data` / `--drop-db` require explicit `--confirm-instance <name>` (plain `--yes` is never accepted).

---

## Operations CLI (`emdashctl`) Reference

All instance-scoped commands accept `[--lang <code>]` and `[--instance <name>]` (defaulting to the primary instance when omitted).

| Command | Purpose |
| --- | --- |
| `emdashctl instances [--json]` | List all native instances on the host with running status, port, DB driver, and URL |
| `emdashctl status [--json]` | Show runtime, app health, setup status, database, session, and Caddy state |
| `emdashctl doctor [--deep] [--json]` | Run health, permission, ownership, migration, and upstream `emdash doctor` checks |
| `emdashctl diagnose [--json] [--lines N] [--out FILE]` | Export a fully redacted AI-friendly diagnostic bundle (`0600`, no symlinks) |
| `emdashctl smoke [--json]` | Run end-to-end local HTTP + setup API smoke check |
| `emdashctl logs [app\|postgres\|redis\|caddy] [-f]` | Inspect systemd service logs |
| `emdashctl restart [app\|postgres\|redis\|caddy\|all]` | Restart one or all stack services |
| `emdashctl backup [--full] [--encrypt] [--list-s3 [--json]]` | Create verified local/S3 backup (with retention pruning) or list remote S3 backups |
| `emdashctl restore <file \| --from-s3 <key\|latest>> [--with-site] [--with-secrets] [--yes]` | Verify checksums/driver and safely restore database, uploads, and optional site/secrets |
| `emdashctl upgrade app [--target <ver\|latest>] [--dry-run] [--skip-backup] [--yes]` | Non-destructive dependency upgrade with pre-upgrade backup and explicit migration gate |
| `emdashctl upgrade caddy-config` | Re-render and validate modular Caddy config without touching user `conf.d/*.caddy` |
| `emdashctl template diff [--stat]` | Compare upstream template changes read-only |
| `emdashctl rotate-encryption-key [--status \| --dry-run \| --prune-old --confirm-prune-kid <kid>]` | Two-stage zero-loss `EMDASH_ENCRYPTION_KEY` rotation |
| `emdashctl migrate-db sqlite-to-postgres [--dry-run] [--yes]` | Migrate an instance from SQLite to PostgreSQL 18 with exact row-count verification |
| `emdashctl reset-db-password` | Rotate native PostgreSQL role password atomically with health-check rollback |
| `emdashctl uninstall [--purge-data] [--drop-db] [--confirm-instance <name>]` | Safely remove an instance without harming sibling instances |

<details>
<summary><strong>Common Installer Environment Variables (click to expand)</strong></summary>

| Variable | Default | Description |
| --- | --- | --- |
| `EMDASH_INSTALL_LANG` | `en` | Installer UI language (`en`, `zh-CN`, `zh-TW`, `ja`, `ko`, `es`, `de`, `fr`, `pt`) |
| `EMDASH_INSTALL_INSTANCE` | *(empty = default)* | Named instance slug (`^[a-z][a-z0-9-]{0,31}$`) for multi-instance hosting |
| `EMDASH_INSTALL_TEMPLATE` | `blog` | Upstream EmDash template (`blog`, `marketing`, `portfolio`) |
| `EMDASH_INSTALL_ROOT_DIR` | `/data/emdash` (or `/data/emdash-<name>`) | Instance root directory |
| `EMDASH_INSTALL_APP_PORT` | `3000` (or auto `3001+`) | Internal Node.js listen port |
| `EMDASH_INSTALL_USE_CADDY` | `1` | Install and configure host Caddy reverse proxy (`1` or `0`) |
| `EMDASH_INSTALL_ENABLE_HTTPS` | `1` | Enable automatic Let's Encrypt HTTPS (`0` for HTTP-only behind CDN/Tunnel/LAN) |
| `EMDASH_INSTALL_DOMAIN` | *(prompted)* | Public site domain when Caddy is enabled |
| `EMDASH_INSTALL_ADMIN_EMAIL` | *(prompted)* | ACME / Caddy global email |
| `EMDASH_INSTALL_DB_DRIVER` | `sqlite` | Database backend (`sqlite` or `postgres` for PostgreSQL 18) |
| `EMDASH_INSTALL_PG_PASSWORD` | *(generated/prompted)* | PostgreSQL role password |
| `EMDASH_INSTALL_SESSION_DRIVER` | `file` | Session store (`file` or `redis` for Valkey 8) |
| `EMDASH_INSTALL_REDIS_PASSWORD` | *(generated/prompted)* | Valkey authentication password |
| `EMDASH_INSTALL_STORAGE_DRIVER` | `local` | Media storage (`local` or `s3`) |
| `EMDASH_INSTALL_ENABLE_PLUGIN_SANDBOX` | `1` | Enable `@emdash-cms/sandbox-workerd` plugin sandbox (`1` or `0`) |
| `EMDASH_INSTALL_ENCRYPTION_KEY` | *(auto-generated)* | Explicit `emdash_enc_v1_...` key for deterministic/DR installs |
| `EMDASH_INSTALL_BACKUP_TARGET` | `local` | Backup destination (`local` or `s3`) |
| `EMDASH_INSTALL_BACKUP_KEEP_S3` | `14` | Number of remote S3 backups retained per prefix |
| `EMDASH_INSTALL_BACKUP_ENCRYPTION_PASSPHRASE` | *(empty)* | Dedicated passphrase for `--encrypt` archives (must differ from `EMDASH_ENCRYPTION_KEY`) |
| `EMDASH_MIRROR_PRESET` | *(empty)* | Set to `cn` for mainland China `npmmirror` + Google Fonts fast-fail acceleration |
| `EMDASH_FAST_FAIL_GOOGLE_FONTS` | `1` under `cn`, else `0` | Fast-fail unreachable Google Fonts metadata requests during build (`0` to disable) |
| `EMDASH_INSTALL_FORCE_SYNC_TEMPLATE` | `0` | Set to `1` to explicitly overwrite an existing `SITE_DIR` with fresh template files |

</details>

<details>
<summary><strong>Native Filesystem Layout (default vs. named instance)</strong></summary>

| Component | Default Instance | Named Instance (`--instance site2`) |
| --- | --- | --- |
| Env & Install Metadata | `/etc/emdash/emdash.env`, `install.yml` | `/etc/emdash/instances/site2/emdash.env`, `install.yml` |
| Data & Site Root | `/data/emdash` (`app/site`, `data/`, `backups/`, `scripts/`, `lib/`) | `/data/emdash-site2` |
| systemd Unit | `/etc/systemd/system/emdash-app.service` | `/etc/systemd/system/emdash-app-site2.service` |
| Backup Cron | `/etc/cron.d/emdash-backup` | `/etc/cron.d/emdash-backup-site2` |
| Caddy Site Snippet | `/etc/emdash/caddy/sites.d/default.caddy` | `/etc/emdash/caddy/sites.d/site2.caddy` |
| User Caddy Snippets | `/etc/emdash/caddy/conf.d/*.caddy` (shared, preserved) | Same |
| PostgreSQL DB / User | `emdash` / `emdash` | `emdash_site2` / `emdash_site2` |
| Global Operations CLI | `/usr/local/bin/emdashctl` | Same |

</details>

---

## Supported Platforms & Verified Matrix

| OS Family | Supported Versions | Architectures | Runtime Stack | Verification Coverage |
| --- | --- | --- | --- | --- |
| **Debian** | 13 (`trixie`) | `x86_64`, `aarch64` | Node 24, PG 18 (PGDG), Valkey, Caddy | Real PVE VM (`x86_64`, 2 GiB RAM + swap + PG 18 + multi-instance + SQLite→PG) |
| **Ubuntu** | 24.04 LTS (`noble`), 26.04 LTS (`resolute`) | `x86_64`, `aarch64` | Node 24, PG 18 (PGDG), Valkey, Caddy | Real PVE/Linode VMs (`x86_64`) + native CI runners |
| **EL-like** (Rocky, Alma, RHEL, OL, CentOS Stream) | 9, 10 | `x86_64`, `aarch64` | Node 24, PG 18 (PGDG dynamic arch), Valkey, Caddy, SELinux Enforcing | Real PVE VMs (`x86_64` Rocky 9.9 / Rocky 10.3 / Alma 10.3 SELinux Enforcing) |
| **Docker / GHCR** | Multi-arch OCI images | `linux/amd64`, `linux/arm64` | Node 24 + `workerd` + optional PG 18 / Valkey 8 / Caddy 2 | Native GitHub Actions `ubuntu-24.04` & `ubuntu-24.04-arm` + local ARM64 E2E |

Detailed verification procedures and the generic remote E2E verifier ([`scripts/remote-e2e-verify.sh`](./scripts/remote-e2e-verify.sh)) are documented in [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md).

---

## Versioning & Compatibility

This repository follows the **`HiEmdash`** version line: `<emdash-version>-hi.<revision>` (e.g. `1.6.0-hi.1` → `1.6.0-hi.5`). When upstream EmDash bumps its base version, the `-hi.<revision>` suffix resets to `1`.

- Unified command interface across all 9 languages: `bootstrap.sh --lang=<code>`, `install.sh --lang=<code>`, `emdashctl --lang=<code>`.
- Legacy language-suffixed alias scripts (`emdashctl.<lang>.sh`) were retired; see [`COMPATIBILITY.md`](./COMPATIBILITY.md) for migration details.

---

## Repository Map

- [`bootstrap.sh`](./bootstrap.sh) — Remote one-liner bootstrapper (passes `--lang`, `--instance`, `--update-cli`, `--non-interactive`, `--write-only`, `--activate`)
- [`install.sh`](./install.sh) / [`install-emdash.sh`](./install-emdash.sh) — Native VPS installer and zero-downtime `--update-cli` updater
- [`emdashctl`](./emdashctl) — Full lifecycle operations CLI (single- and multi-instance)
- [`lib/`](./lib/) — Modular installer & runtime libraries:
  - [`lib/site-common.sh`](./lib/site-common.sh) & [`lib/astro-patch.py`](./lib/astro-patch.py) — Shared single source of truth for Native & Docker
  - [`lib/migrate-sqlite-to-pg.py`](./lib/migrate-sqlite-to-pg.py) — Zero-dependency SQLite → PostgreSQL 18 migrator
  - [`lib/fast-fail-google-fonts.mjs`](./lib/fast-fail-google-fonts.mjs) — Non-invasive Node `--import` font fast-fail hook
  - [`lib/config.sh`](./lib/config.sh), [`lib/os.sh`](./lib/os.sh), [`lib/render.sh`](./lib/render.sh), [`lib/network.sh`](./lib/network.sh), [`lib/i18n.sh`](./lib/i18n.sh), [`lib/prompt.sh`](./lib/prompt.sh), [`lib/common.sh`](./lib/common.sh)
- [`docker/`](./docker/README.md) — Coexistence-first Docker Compose kit, overlays, `Dockerfile`, `Dockerfile.custom`, `backup.sh`, `restore.sh`
- [`scripts/`](./scripts/) — Runtime migration helper (`migrate-runtime.sh`), remote E2E verifier (`remote-e2e-verify.sh`), and 13 offline regression test suites
- [`AGENTS.md`](./AGENTS.md) — Engineering handbook, invariants, pitfalls, and verification gates for AI coding agents & contributors
- [`CHANGELOG.md`](./CHANGELOG.md) — Complete release history and validation evidence
