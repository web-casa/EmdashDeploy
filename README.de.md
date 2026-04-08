# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | **Deutsch** | [Français](./README.fr.md) | [Português](./README.pt.md)

Ein interaktiver VPS-Installer und Betriebswerkzeugkasten für EmDash mit Docker/Podman, optionalem Caddy HTTPS, Backup, Restore und Health Checks.

## Zweck

Dieses Repository dient dazu, EmDash auf einem VPS bereitzustellen und den laufenden Betrieb mit einfachen Werkzeugen zu unterstützen.

## Funktionen

- Installer: [`install.sh`](./install.sh)
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
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=de
```

Nur Dateien erzeugen:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=de --write-only
```

## GHCR

Das Repository enthält Workflows zum Veröffentlichen des Builder-Images und eines Standard-App-Images nach GHCR.

- Workflow: [`publish-ghcr-builder.yml`](./.github/workflows/publish-ghcr-builder.yml)
- Workflow: [`publish-ghcr-app.yml`](./.github/workflows/publish-ghcr-app.yml)
- Dockerfile: [`docker/base/Dockerfile`](./docker/base/Dockerfile)
- Builder-Image: `ghcr.io/<repository_owner>/emdash-builder:node24-bookworm`
- Standard-App-Image: `ghcr.io/<repository_owner>/emdash-app:starter-sqlite-file-local`

Unterschied zwischen `builder` und `app`:

- `builder` ist ein wiederverwendbares Build-Umgebungs-Image.
- `app` ist ein bereits gebautes Runtime-Image.

`builder` passt besser, wenn:

- der VPS die Site lokal bauen soll
- PostgreSQL, Redis oder S3-kompatibler Storage verwendet wird
- du das Template geändert hast oder maximale Flexibilität willst

`app` passt besser, wenn:

- du den schnellsten Deployment-Pfad willst
- du lokale App-Builds auf dem VPS vermeiden willst
- du das Standardprofil `starter + sqlite + file + local` verwendest

Beispiel:

```bash
EMDASH_INSTALL_APP_BASE_IMAGE=ghcr.io/<owner>/emdash-builder:node24-bookworm \
sudo bash install.sh --lang=de --activate
```

Beispiel mit vorgebautem App-Image:

```bash
EMDASH_INSTALL_APP_IMAGE=ghcr.io/<owner>/emdash-app:starter-sqlite-file-local \
sudo bash install.sh --lang=de --activate
```

Empfehlung:

- Für allgemeine oder angepasste Deployments `APP_BASE_IMAGE` bevorzugen
- Für das Standardprofil mit SQLite/file/local `APP_IMAGE` bevorzugen

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

Für Betriebsbefehle kannst du den deutschen Wrapper verwenden:

```bash
emdashctl --lang=de status
emdashctl --lang=de doctor
emdashctl --lang=de smoke
emdashctl --lang=de logs app -f
emdashctl --lang=de backup
emdashctl --lang=de restore /path/to/backup.tar.gz
```
