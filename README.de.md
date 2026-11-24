# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | **Deutsch** | [Français](./README.fr.md) | [Português](./README.pt.md)

Nativer VPS-Installer und Betriebswerkzeugkasten für EmDash `1.6.x` mit Node.js 24, systemd, optionalem Caddy HTTPS, Backup, Restore, KI-Diagnosepaket und sicherer Schlüsselrotation.

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

## Überblick

`main` installiert EmDash nativ auf dem VPS-Host. Für Server mit mehreren Diensten oder mehreren EmDash-Instanzen liegt zusätzlich das koexistenzfähige Docker-Compose-Kit unter [`docker/`](./docker/README.md) bereit (native GHCR Multi-Arch-Images für `amd64`/`arm64`, bindet standardmäßig weder Port 80 noch 443). Der frühere Container-Installer bleibt im Branch `docker` archiviert.

## Unterstützte Plattformen (`x86_64` / `aarch64`)

| System | Versionen | Hinweise |
| --- | --- | --- |
| Debian | 13 (`trixie`) | Native Installation |
| Ubuntu | 24.04 LTS (`noble`), 26.04 LTS (`resolute`) | Native Installation |
| EL-like | 9, 10 | Native Installation |

- Node.js 24 (`NodeSource`), PostgreSQL 18 (`PGDG`), Session-Cache über `Valkey` (automatische systemd-Unit-Erkennung)
- EmDash `1.6.x`: `EMDASH_ENCRYPTION_KEY` (2-stufige Rotation), `@emdash-cms/sandbox-workerd` Plugin-Sandbox, explizite `emdash migrate`-Prüfung, `EMDASH_MIRROR_PRESET=cn`
- Testabdeckung: Debian 13 / Ubuntu 24.04 / Ubuntu 26.04 / EL9 / EL10 auf realen `x86_64`-VMs verifiziert; `ARM64`-Container-Images und `workerd` nativ auf GitHub Actions `ubuntu-24.04-arm` getestet

## Häufige Befehle

```bash
emdashctl --lang=de status [--json]
emdashctl --lang=de doctor --deep --json
emdashctl --lang=de diagnose --json --out /tmp/emdash-diag.json
emdashctl --lang=de smoke [--json]
emdashctl --lang=de backup [--full] [--encrypt]
emdashctl --lang=de restore /path/to/backup.tar.gz [--with-site] [--with-secrets]
emdashctl --lang=de upgrade app [--dry-run] [--target <version|latest>]
emdashctl --lang=de template diff [--stat]
emdashctl --lang=de rotate-encryption-key [--status | --dry-run | --prune-old --confirm-prune-kid <kid>]
emdashctl --lang=de reset-db-password
```

## Bekannte Grenzen

- Änderungen an Templates, Plugins oder Build-Konfiguration erfordern weiterhin `pnpm build`
- `upgrade` unterstützt derzeit nur `app` und `caddy-config`
- eigene Skripte und user crontabs werden nicht automatisch migriert

Weitere Details in [README.md](./README.md), [`docker/README.md`](./docker/README.md), [`COMPATIBILITY.md`](./COMPATIBILITY.md) und [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md).
