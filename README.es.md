# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | **Español** | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [Português](./README.pt.md)

Instalador nativo para VPS y conjunto de herramientas operativas para EmDash `1.6.x` con Node.js 24, systemd, Caddy HTTPS opcional, copias de seguridad, diagnóstico para IA y rotación segura de claves.

## Inicio rápido

Instalación interactiva:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=es
```

Solo generar configuración:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=es --write-only
```

Instalación no interactiva:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=es --non-interactive --activate
```

## Resumen

`main` instala EmDash de forma nativa en el host VPS. Para servidores que comparten varios servicios o varias instancias de EmDash, también incluye el kit ligero Docker Compose en [`docker/`](./docker/README.md) (imágenes multiarquitectura GHCR `amd64`/`arm64`, sin ocupar los puertos 80/443 por defecto). El antiguo instalador en contenedores permanece archivado en la rama `docker`.

Compatibilidad (`x86_64` / `aarch64`):

- Debian 13 (`trixie`)
- Ubuntu 24.04 LTS (`noble`) / 26.04 LTS (`resolute`)
- EL9 / EL10
- SQLite / PostgreSQL 18 (PGDG)
- file session / Valkey
- almacenamiento local / compatible con S3, Caddy + HTTPS
- EmDash `1.6.x`: `EMDASH_ENCRYPTION_KEY` (rotación en 2 fases), sandbox de plugins `@emdash-cms/sandbox-workerd`, puerta de migraciones `emdash migrate`, `EMDASH_MIRROR_PRESET=cn`

## Comandos principales

```bash
emdashctl --lang=es status [--json]
emdashctl --lang=es doctor --deep --json
emdashctl --lang=es diagnose --json --out /tmp/emdash-diag.json
emdashctl --lang=es smoke [--json]
emdashctl --lang=es backup [--full] [--encrypt]
emdashctl --lang=es restore /path/to/backup.tar.gz [--with-site] [--with-secrets]
emdashctl --lang=es instances [--json]
emdashctl --lang=es [--instance <name>] upgrade app [--dry-run] [--target <version|latest>]
emdashctl --lang=es [--instance <name>] template diff [--stat]
emdashctl --lang=es [--instance <name>] rotate-encryption-key [--status | --dry-run | --prune-old --confirm-prune-kid <kid>]
emdashctl --lang=es [--instance <name>] migrate-db sqlite-to-postgres [--dry-run] [--yes]
emdashctl --lang=es [--instance <name>] reset-db-password
emdashctl --lang=es [--instance <name>] uninstall [--purge-data] [--drop-db] [--confirm-instance <name>]
sudo bash install.sh --update-cli
```

## Alcance verificado y límites

- Debian 13 / Ubuntu 24.04 / Ubuntu 26.04 / EL9 / EL10 están verificados en máquinas virtuales reales `x86_64`; las imágenes de contenedor `ARM64` y `workerd` se validan de forma nativa en GitHub Actions `ubuntu-24.04-arm`.
- Los cambios de plantilla, plugins y configuración de build siguen requiriendo `pnpm build`.
- `upgrade` solo admite `app` y `caddy-config`.

Más detalles en [README.md](./README.md), [`docker/README.md`](./docker/README.md), [`COMPATIBILITY.md`](./COMPATIBILITY.md) y [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md).
