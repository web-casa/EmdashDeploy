# EmdashDeploy Docker Compose Kit (`1.6.0-hi.5`)

A lightweight, composable Docker Compose kit for running **EmDash `1.6.x`** alongside other services (or multiple EmDash sites) on a single VPS.

- **Prebuilt multi-arch GHCR images**: Native `linux/amd64` and `linux/arm64` images published to `ghcr.io/web-casa/emdash-deploy` with SBOM & provenance attestations.
- **Prebuilt vs. local build decoupled**: `compose.yml` references prebuilt images only (`image:`); local builds and mainland China mirrors use the separate `compose.build.yml` overlay with independent local tags.
- **Single source of truth**: Reuses `lib/site-common.sh` and `lib/astro-patch.py` directly from `main`.
- **Coexistence-first**: Does **not** bind host ports `80/443` by default (binds `127.0.0.1:${APP_PORT:-3000}` only).
- **EmDash `1.6.x` native features**: Supports `EMDASH_ENCRYPTION_KEY` persistence/validation, `@emdash-cms/sandbox-workerd` plugin sandbox, explicit `emdash migrate` checks, and `Valkey 8` + `PostgreSQL 18` profiles.

---

## Quick Start (Prebuilt GHCR Image — SQLite)

```bash
cd docker
cp .env.example .env
# Edit .env: set EMDASH_SITE_URL=https://blog.example.com and APP_PORT=3001
# Generate an encryption key once:
docker compose run --rm emdash secrets-generate
# Paste the generated key into EMDASH_ENCRYPTION_KEY in .env, then start:
docker compose up -d
```

Point your existing Nginx / Caddy / Traefik / 1Panel site to `http://127.0.0.1:3001`.

---

## Production Stack (PostgreSQL 18 + Valkey 8)

In `.env`:

```dotenv
EMDASH_IMAGE=ghcr.io/web-casa/emdash-deploy:1.6.0-hi.5-blog-pg-valkey
DB_DRIVER=postgres
SESSION_DRIVER=redis
PG_DB_PASSWORD=replace-with-strong-pg-password
REDIS_PASSWORD=replace-with-strong-valkey-password
REDIS_URL=redis://:replace-with-strong-valkey-password@valkey:6379/0
EMDASH_SITE_URL=https://blog.example.com
```

Start with profiles:

```bash
docker compose --profile postgres --profile valkey up -d
```

> Database passwords (`PG_DB_PASSWORD`), S3 secrets, and `EMDASH_ENCRYPTION_KEY` are resolved purely at runtime and are **never baked into any Docker image**.

---

## Local Build & Mainland China Accelerated Build (`compose.build.yml`)

To build locally (for example, to use the `marketing` or `portfolio` template, S3 storage, or mainland China mirrors), layer `compose.build.yml` so local tags (`emdash-deploy:local-...`) stay cleanly separated from GHCR tags:

```dotenv
# Optional mainland China mirrors in .env:
NPM_CONFIG_REGISTRY=https://registry.npmmirror.com
COREPACK_NPM_REGISTRY=https://registry.npmmirror.com
EMDASH_TEMPLATES_REPO=https://gh-proxy.com/https://github.com/emdash-cms/templates.git
EMDASH_FAST_FAIL_GOOGLE_FONTS=1
```

```bash
docker compose -f compose.yml -f compose.build.yml up -d --build
```

---

## Custom EmDash Site Repository (`compose.custom-site.yml`)

For a custom or AI-Coding-modified EmDash site, build an isolated non-root image directly from your site directory (never bind-mount a host directory over `/app/site` or mutate your source files):

```bash
CUSTOM_SITE_DIR=/path/to/your-emdash-site \
  docker compose -f compose.yml -f compose.custom-site.yml up -d --build
```

`Dockerfile.custom` respects your own `packageManager`, `pnpm-lock.yaml`, and `astro.config.*` verbatim.

---

## Running Multiple EmDash Sites on One Server

Create separate `.env` files (or separate directories) with distinct `COMPOSE_PROJECT_NAME` and `APP_PORT`:

```bash
# Site A on 127.0.0.1:3001
docker compose --env-file .env.site-a -p emdash-site-a up -d

# Site B on 127.0.0.1:3002
docker compose --env-file .env.site-b -p emdash-site-b up -d
```

### Attach to an Existing Reverse-Proxy Docker Network (Zero Host Ports)

```bash
docker network create proxy   # once on host
PROXY_NETWORK=proxy docker compose -f compose.yml -f compose.proxy-net.yml up -d
```

Then configure your proxy container (Nginx Proxy Manager / Traefik / Caddy) to forward to `http://<service-or-container>:3000`.

---

## Optional Bundled Caddy

If this host does not already run a reverse proxy:

```bash
cp Caddyfile.example Caddyfile
# Edit domain & email in Caddyfile
docker compose --profile caddy up -d
```

---

## Container-Safe Backups & Restores (`docker/backup.sh` & `docker/restore.sh`)

```bash
# Unencrypted archive (0600 permissions)
bash docker/backup.sh --env-file docker/.env --out-dir ./backups

# Encrypted archive (uses a dedicated passphrase separate from EMDASH_ENCRYPTION_KEY)
BACKUP_ENCRYPTION_PASSPHRASE='separate-backup-passphrase' \
  bash docker/backup.sh --env-file docker/.env --out-dir ./backups --encrypt

# Restore (validates tar safety, manifest driver, and SHA-256 checksums before mutating state)
BACKUP_ENCRYPTION_PASSPHRASE='separate-backup-passphrase' \
  bash docker/restore.sh ./backups/emdash-blog-backup-*.tar.gz.enc --env-file docker/.env --yes
```

- SQLite backup uses `sqlite3.backup()` + `PRAGMA integrity_check`; restore stops `emdash`, removes `-wal`/`-shm`, atomically swaps `/data/sqlite/data.db` with `PUID:PGID` ownership, and verifies `PRAGMA integrity_check` + `/healthz`.
- PostgreSQL backup uses `pg_dump -Fc` + `pg_restore --list`; restore loads into a fresh temporary database and atomically swaps databases.

---

## Two-Stage Encryption Key Rotation (Docker)

EmDash `1.6.x` supports comma-separated keys in `EMDASH_ENCRYPTION_KEY` (the first key encrypts new writes; subsequent keys remain active for decrypting legacy envelopes):

1. **Stage 1 (Add new key)**:
   ```bash
   NEW_KEY="$(docker compose run --rm emdash secrets-generate | tail -n 1)"
   # In .env, set: EMDASH_ENCRYPTION_KEY=<NEW_KEY>,<OLD_KEY>
   docker compose up -d
   ```
2. **Stage 2 (Prune old key)**:
   After re-saving any encrypted plugin settings in EmDash Admin so no legacy `kid` envelopes remain in the database, remove `<OLD_KEY>` from `EMDASH_ENCRYPTION_KEY` in `.env` and run `docker compose up -d`.

---

## Migrating Between Docker Compose and Native systemd

Use [`scripts/migrate-runtime.sh`](../scripts/migrate-runtime.sh) to move backups and `EMDASH_ENCRYPTION_KEY` cleanly in either direction:

```bash
# Native backup -> Docker Compose deployment directory (.env created with 0600 permissions)
bash scripts/migrate-runtime.sh native-to-docker \
  --backup /data/emdash/backups/emdash-backup-*.tar.gz --out-dir ./my-docker-emdash

# Docker backup -> Native systemd instance (dry-run preview first)
bash scripts/migrate-runtime.sh docker-to-native \
  --backup ./backups/emdash-blog-backup-*.tar.gz --docker-env docker/.env --dry-run
```

---

## Operations Commands

```bash
# Generate a fresh EMDASH_ENCRYPTION_KEY for .env
docker compose run --rm emdash secrets-generate

# Inspect migration status without mutating DB
docker compose run --rm emdash migrate-status

# Run database migrations explicitly (e.g. when EMDASH_AUTO_MIGRATE=0)
docker compose run --rm emdash migrate

# Run container-level diagnostics (JSON, redacted)
docker compose exec emdash /usr/local/bin/emdash-entrypoint.sh doctor
```
