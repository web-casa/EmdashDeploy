# EmdashDeploy Docker Compose Kit (`1.6.0-hi.1`)

A lightweight, composable Docker Compose kit for running **EmDash `1.6.x`** alongside other services (or multiple EmDash sites) on a single VPS.

- **Single source of truth**: Reuses `lib/site-common.sh` and `lib/astro-patch.py` directly from `main`.
- **Coexistence-first**: Does **not** bind host ports `80/443` by default (binds `127.0.0.1:${APP_PORT:-3000}` only).
- **EmDash `1.6.x` native features**: Supports `EMDASH_ENCRYPTION_KEY` persistence/validation, `@emdash-cms/sandbox-workerd` plugin sandbox, explicit `emdash migrate` checks, and `Valkey` + `PostgreSQL 18` profiles.

---

## Quick Start (SQLite + Existing Host Reverse Proxy)

```bash
cd docker
cp .env.example .env
# Edit .env: set EMDASH_SITE_URL=https://blog.example.com and APP_PORT=3001
docker compose build
docker compose up -d
```

Point your existing Nginx / Caddy / Traefik / 1Panel site to `http://127.0.0.1:3001`.

---

## Production Stack (PostgreSQL 18 + Valkey)

In `.env`:

```dotenv
DB_DRIVER=postgres
SESSION_DRIVER=redis
PG_DB_PASSWORD=replace-with-strong-pg-password
REDIS_PASSWORD=replace-with-strong-valkey-password
REDIS_URL=redis://:replace-with-strong-valkey-password@valkey:6379/0
EMDASH_SITE_URL=https://blog.example.com
```

Build and start with profiles:

```bash
docker compose --profile postgres --profile valkey up -d --build
```

> Note: Because Astro builds driver integrations into the server bundle, pass `--build` when switching `DB_DRIVER`, `SESSION_DRIVER`, `STORAGE_DRIVER`, or `ENABLE_PLUGIN_SANDBOX`. Database passwords (`PG_DB_PASSWORD`), S3 secrets, and `EMDASH_ENCRYPTION_KEY` are resolved purely at runtime and are **never baked into the Docker image**.

---

## Running Multiple EmDash Sites on One Server

Create separate `.env` files (or separate directories) with distinct `COMPOSE_PROJECT_NAME` and `APP_PORT`:

```bash
# Site A on 127.0.0.1:3001
docker compose --env-file .env.site-a -p emdash-site-a up -d --build

# Site B on 127.0.0.1:3002
docker compose --env-file .env.site-b -p emdash-site-b up -d --build
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

## Mainland China Accelerated Build

Uncomment these in `.env` before `docker compose build`:

```dotenv
NPM_CONFIG_REGISTRY=https://registry.npmmirror.com
COREPACK_NPM_REGISTRY=https://registry.npmmirror.com
EMDASH_TEMPLATES_REPO=https://gh-proxy.com/https://github.com/emdash-cms/templates.git
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
