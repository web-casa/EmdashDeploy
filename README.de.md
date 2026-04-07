# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [日本語](./README.ja.md) | **Deutsch** | [Français](./README.fr.md) | [한국어](./README.ko.md)

Ein interaktiver VPS-Installer und Betriebswerkzeugkasten für EmDash mit Docker/Podman, optionalem Caddy HTTPS, Backup, Restore und Health Checks.

## Zweck

Dieses Repository dient dazu, EmDash auf einem VPS bereitzustellen und den laufenden Betrieb mit einfachen Werkzeugen zu unterstützen.

## Funktionen

- Installer: [`install-emdash.sh`](./install-emdash.sh)
- Betriebs-CLI: [`emdashctl`](./emdashctl)
- Reale VPS-Tests über Linode: [`linode-test.sh`](./linode-test.sh)
- SQLite oder PostgreSQL 18
- File-basierte Sessions oder Redis
- Lokales Dateisystem oder S3-kompatibler Speicher
- Optionales natives Caddy auf dem Host

## Unterstützte Plattformen

| System | Versionen | Runtime |
| --- | --- | --- |
| Debian | 12, 13 | Docker |
| Ubuntu | 22.04, 24.04 | Docker |
| EL-like | 8, 9, 10 | Podman |

Nicht unterstützt:

- SLES family
- Turso / libSQL

## Schnellstart

```bash
git clone https://github.com/web-casa/EmdashDeploy.git
cd EmdashDeploy
chmod +x install-emdash.sh emdashctl linode-test.sh
sudo bash install-emdash.sh
```

Direkt aktivieren:

```bash
sudo bash install-emdash.sh --activate
```

## GHCR

Das Repository enthält einen Workflow zum Veröffentlichen des Builder-Images nach GHCR.

- Workflow: [`publish-ghcr-builder.yml`](./.github/workflows/publish-ghcr-builder.yml)
- Dockerfile: [`docker/base/Dockerfile`](./docker/base/Dockerfile)
- Image: `ghcr.io/<repository_owner>/emdash-builder:node24-bookworm`

Beispiel:

```bash
EMDASH_INSTALL_APP_BASE_IMAGE=ghcr.io/<owner>/emdash-builder:node24-bookworm \
sudo bash install-emdash.sh --activate
```

## HTTPS

Wenn Caddy aktiviert wird, prüft der Installer öffentliche IPs, DNS, die Ports `80/443`, installiert Caddy auf dem Host und richtet HTTPS ein.

Unter EL werden Regeln für `firewalld` automatisch gesetzt. Unter Debian/Ubuntu werden Regeln für `ufw` gesetzt, falls `ufw` aktiv ist.

## VPS-Tests

```bash
cp .env.example .env
```

Dann:

```bash
linode_token=YOUR_TOKEN_HERE
```

Test starten:

```bash
bash linode-test.sh
```

Weitere Details stehen in [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md).
