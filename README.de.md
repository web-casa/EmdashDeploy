# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | **Deutsch** | [Français](./README.fr.md) | [Português](./README.pt.md)

Nativer VPS-Installer und Betriebswerkzeugkasten für EmDash mit Node.js, systemd, optionalem Caddy HTTPS, Backup, Restore und Health Checks.

## Schnellstart

Interaktive Installation:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=de
```

Nur Konfiguration erzeugen:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=de --write-only
```

Nicht-interaktive Installation:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=de --non-interactive --activate
```

Lokaler Checkout:

```bash
git clone https://github.com/web-casa/EmdashDeploy.git
cd EmdashDeploy
chmod +x bootstrap.sh install.sh emdashctl linode-test.sh
sudo bash install.sh --lang=de --activate
```

Einheitliche Einstiegspunkte:

- `bootstrap.sh --lang=<code>`
- `install.sh --lang=<code>`
- `emdashctl --lang=<code>`

## Zweck

Dieses Repository installiert EmDash direkt nativ auf dem VPS-Host.

Geeignet für:

- interaktive Installation
- nicht-interaktive Installation per Umgebungsvariablen
- nativen Node.js + systemd-Betrieb
- Caddy + HTTPS
- SQLite oder PostgreSQL 18
- file sessions oder Redis
- lokales Dateisystem oder S3-kompatiblen Speicher
- Backup, Restore, Health Checks und Upgrades

Die frühere Container-Implementierung liegt archiviert im Branch `docker`. `main` ist jetzt nur noch für native Deployments.

## Unterstützte Plattformen

| System | Versionen | Hinweise |
| --- | --- | --- |
| Debian | 13 | Native Installation |
| Ubuntu | 24.04 | Native Installation |
| EL-like | 9, 10 | Native Installation |

Zusätzlich:

- Node.js über `NodeSource`
- PostgreSQL 18 über `PGDG`
- Redis aus dem Systempaket
- unter EL10 automatische Anpassung an `valkey`

## Funktionen

- Installer: [`install.sh`](./install.sh)
- Betriebs-CLI: [`emdashctl`](./emdashctl)
- Reale Linode-VPS-Tests: [`linode-test.sh`](./linode-test.sh)
- nativer `systemd`-Dienst
- natives Caddy
- SQLite / PostgreSQL 18
- file / Redis sessions
- local / S3-kompatibler Speicher
- S3-Backups

## Nicht-interaktive Beispiele

```bash
EMDASH_INSTALL_DB_DRIVER=sqlite \
EMDASH_INSTALL_SESSION_DRIVER=file \
EMDASH_INSTALL_STORAGE_DRIVER=local \
sudo bash install.sh --lang=de --non-interactive --activate
```

```bash
EMDASH_INSTALL_DB_DRIVER=postgres \
EMDASH_INSTALL_PG_PASSWORD='change-me-now' \
EMDASH_INSTALL_SESSION_DRIVER=redis \
EMDASH_INSTALL_REDIS_PASSWORD='change-me-too' \
sudo bash install.sh --lang=de --non-interactive --activate
```

## Häufige Befehle

```bash
emdashctl --lang=de status
emdashctl --lang=de doctor
emdashctl --lang=de smoke
emdashctl --lang=de backup
emdashctl --lang=de restore /path/to/backup.tar.gz
emdashctl --lang=de upgrade app
emdashctl --lang=de reset-db-password
```

## Migration vom Branch `docker`

Wenn du Docker/Podman weiter nutzen willst, bleibe beim Branch `docker`.
Für die native Variante verwende `main`.

Wichtige Unterschiede:

- kein `compose.yml`
- keine Container-Runtime nötig
- App läuft unter `systemd`
- PostgreSQL / Redis / Caddy werden direkt auf dem Host installiert

## Bekannte Grenzen

- `main` bietet kein Docker/Podman-Deployment mehr
- nur Debian 13, Ubuntu 24.04, EL9 und EL10 werden unterstützt
- Änderungen an Templates, Plugins oder Build-Konfiguration erfordern weiterhin `pnpm build`
- `upgrade` unterstützt derzeit nur `app` und `caddy-config`
- eigene Skripte, user crontabs und alte raw-URLs werden nicht automatisch migriert

Weitere Details in [`COMPATIBILITY.md`](./COMPATIBILITY.md) und [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md).
