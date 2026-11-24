# Changelog

All notable changes to this project are documented in this file.

## 0.3.0-hi.2 - 2026-11-24

Lightweight multi-service / multi-instance Docker Compose kit for EmDash `1.6.x` on `main`.

### Added

- Composable Docker Compose kit under [`docker/`](./docker/README.md):
  - [`docker/Dockerfile`](./docker/Dockerfile): Node.js 24 image reusing `lib/site-common.sh` and `lib/astro-patch.py`, supporting EmDash `1.6.x`, `@emdash-cms/sandbox-workerd`, `HEALTHCHECK`, `tini`, and optional mainland China registry build args (`NPM_CONFIG_REGISTRY`, `COREPACK_NPM_REGISTRY`)
  - [`docker/entrypoint.sh`](./docker/entrypoint.sh): non-root `PUID`/`PGID` alignment, persistent/validated `EMDASH_ENCRYPTION_KEY`, PostgreSQL readiness wait, explicit `emdash migrate` gate (`start`, `migrate`, `migrate-status`, `secrets-generate`, `doctor`)
  - [`docker/compose.yml`](./docker/compose.yml): coexistence-first stack (binds `127.0.0.1:${APP_PORT:-3000}` only, no host `80/443` conflict) with optional `postgres` (PG 18), `valkey` (Valkey 8), and `caddy` profiles
  - [`docker/compose.proxy-net.yml`](./docker/compose.proxy-net.yml): zero-host-port overlay for attaching to an existing reverse-proxy Docker network
  - [`docker/.env.example`](./docker/.env.example) & [`docker/Caddyfile.example`](./docker/Caddyfile.example)
- Compose regression test [`scripts/test-docker-compose-regression.sh`](./scripts/test-docker-compose-regression.sh) wired into `.github/workflows/ci.yml`

### Changed

- Updated [`lib/astro-patch.py`](./lib/astro-patch.py) PostgreSQL config fields to emit `|| undefined` when build-time env vars are absent so container images stay 100% secret-free and resolve `PGHOST`/`PGPORT`/`PGDATABASE`/`PGUSER`/`PGPASSWORD` purely at runtime
- Replaced legacy `docker/base/Dockerfile` with the unified `docker/Dockerfile`

## 0.3.0-hi.1 - 2026-11-24

EmDash `1.6.x` compatibility and lifecycle reliability release for the `HiEmdash` native deployment line.

### Added

- Shared site management library [`lib/site-common.sh`](./lib/site-common.sh) deployed atomically to `${ROOT_DIR}/lib/site-common.sh` and included in rollback snapshots
- EmDash `1.6.x` native security and plugin isolation:
  - `EMDASH_ENCRYPTION_KEY` generation via `pnpm exec emdash secrets generate` with `fingerprint` verification
  - `@emdash-cms/sandbox-workerd` + `workerd` plugin sandbox support (enabled by default, configurable via `EMDASH_INSTALL_ENABLE_PLUGIN_SANDBOX`)
- Non-destructive `emdashctl upgrade app` workflow (`--dry-run`, `--target`, `--skip-backup`, `--yes`) with `flock` locking, pre-upgrade verified backup, explicit `emdash migrate --status --json` / `emdash migrate` gate, and pre/post-migration rollback separation
- Read-only `emdashctl template diff [--stat]` to compare upstream template updates without overwriting user code
- Enhanced `emdashctl backup [--full] [--encrypt]` with `0600` permissions, `manifest.json` + SHA256 checksums, lightweight site source snapshot (excluding `node_modules`/`dist`/`.astro`/`.git`), SQLite `PRAGMA integrity_check`, PostgreSQL custom dump (`pg_dump -Fc`) + `pg_restore --list` verification, and optional AES-256-CBC PBKDF2 encryption
- Safe `emdashctl restore <archive> [--with-site] [--with-secrets]` with cross-driver guard and portable-secret-only merge (never overwrites host domain, ports, or DB credentials)
- Full-stack redacted diagnostics via `emdashctl doctor --deep --json` (`schema_version: 1`)
- Mainland China mirror acceleration preset (`EMDASH_MIRROR_PRESET=cn`, application/registry layer only without modifying host APT/DNF system repositories)
- GitHub Actions CI (`.github/workflows/ci.yml` and `.github/workflows/upstream-compat.yml`) and 4 new offline regression test suites

### Changed

- Removed discontinued `blank` template option (`blog`, `marketing`, `portfolio` supported; existing legacy instances preserved with migration notice)
- Stopped hardcoding `pnpm@10.28.0` and `kysely@^0.27.6`; Corepack now respects each site's `packageManager` field with `COREPACK_ENABLE_DOWNLOAD_PROMPT=0`
- Hardened `lib/astro-patch.py` to support tab/space indentation, `sandboxRunner` injection, and strict idempotency
- Updated `emdashctl reset-db-password` to preserve user `astro.config.mjs` and validate the real DB-backed `/_emdash/api/setup/status` endpoint

### Fixed

- Removed container-era dead helpers (`compose_cmd`, `run_compose`, `scripts/prepare-app-context.sh`)
- Fixed `emdashctl doctor` reporting `backup schedule` as `fail` when `BACKUP_ENABLED=0` (now `skipped`)
- Fixed `install-emdash.sh` NAT-friendly local setup status probe when Caddy is disabled

### Validation Summary

- All 7 offline regression suites + `bash -n` + `py_compile` pass
- Real PVE AlmaLinux 10.2 (SELinux enforcing, mainland China network with `EMDASH_MIRROR_PRESET=cn`) E2E verification passed across fresh install (PG 18 + Valkey + `sandbox-workerd`), `doctor --deep --json`, non-destructive `upgrade app`, `template diff`, encrypted `--full` backup & `--with-site --with-secrets` restore, and `reset-db-password`

## 0.2.0-hi.2 - 2026-04-09

Native deployment release for the `HiEmdash` line. `main` now ships the host-based installer and operations flow; the previous container-based implementation remains archived on the `docker` branch.

### Changed

- Switched `main` from Docker/Podman deployment to native Node.js + systemd deployment
- Standardized installer, bootstrap, and operator entrypoints on `--lang`
- Rewrote repository documentation and VPS test plan for native deployment
- Updated upgrade behavior to the native host workflow: template refresh, `pnpm install`, `pnpm build`, and service restart

### Added

- Native install path for Debian 13, Ubuntu 24.04, EL9, and EL10
- Native `systemd` service generation for `emdash-app`
- Native package installation via NodeSource, PGDG, and system packages
- Native Caddy, PostgreSQL, Redis/Valkey, S3 storage, and S3 backup support
- Native release-prep VPS operator validation for backup, restore, password reset, upgrade, and reboot

### Fixed

- PostgreSQL restore now makes extracted dumps readable to the `postgres` OS user
- PostgreSQL password reset now updates the role safely and rebuilds the app so baked connection settings stay in sync
- Native Redis service/path handling on EL9 and EL10
- Native Caddy installation ordering where package auto-start could block HTTPS validation
- Native S3 storage and backup flows with `boto3`-based verification
- Linode native test reliability around SSH host keys and workspace upload

### Validation Summary

Validated with real native VPS testing for:

- Debian 13
- Ubuntu 24.04
- EL9
- EL10
- SQLite, PostgreSQL, Redis/Valkey
- Caddy + HTTPS
- S3-compatible media storage
- S3 backup
- `emdashctl backup`, `restore`, `upgrade app`, `reset-db-password`, and reboot/autostart

### Notes

- `main` is native deployment only as of this release.
- The archived container-based implementation remains available on the `docker` branch.

## 0.2.0-hi.1 - 2026-04-08

First validated HiEmdash production release for VPS deployment.

### Added

- Interactive and non-interactive EmDash VPS installer
- `emdashctl` for status, logs, smoke checks, backup, restore, restart, upgrades, and PostgreSQL password reset
- Native `Caddy` install path with automatic HTTPS
- `Docker` support for Debian 12/13 and Ubuntu 22/24
- `Podman` support for Rocky/Alma/RHEL-like EL 8/9/10
- `SQLite` and `PostgreSQL 18` deployment modes
- `file` and `Redis` session modes
- `local filesystem` and `S3-compatible` storage support
- GHCR builder and app images
- `linux/amd64` and `linux/arm64` image manifests
- Linode-based VPS validation scripts and matrix runner

### Changed

- Standardized health probes on `/healthz`
- Stabilized release tagging and GHCR publish flow for branch/tag separation
- Improved Caddy handling on EL systems with state-directory preparation and SELinux relabel fallback
- Refined backup behavior to keep local artifacts and support verified S3 uploads
- Expanded real-VPS test coverage across Docker, Podman, amd64, and arm64

### Fixed

- PostgreSQL password reset now updates runtime config correctly
- PostgreSQL restore flow now avoids destructive early cutover
- SQLite backup and restore handling improved for WAL safety
- S3 backup upload path now returns proper failure codes
- Podman and Linode test runner edge cases around retries, labels, and flow control
- Caddy certificate issuance on ARM64/EL where `/var/lib/caddy` was not prepared

### Validation Summary

Validated with real VPS testing for:

- Debian 13
- Ubuntu 24
- CentOS Stream 9
- CentOS Stream 10
- AlmaLinux 10
- amd64 and arm64 hosts
- SQLite, PostgreSQL, Redis, Caddy + HTTPS, S3 backup, restore, and password reset flows

### Known Caveat

One arm64 AlmaLinux 10 cloud environment showed external interference on public `80/443` despite successful in-host TLS issuance and local HTTPS validation. Non-standard public ports remained reachable on the same host. This indicates provider or edge-network behavior rather than an installer defect.

## v0.1.0 - 2026-04-07

Initial public repository release with installer, tooling, repository metadata, and translated READMEs.
