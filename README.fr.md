# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Deutsch](./README.de.md) | **Français** | [Português](./README.pt.md)

Installateur VPS natif et boîte à outils d’exploitation pour EmDash `1.6.x` avec Node.js 24, systemd, Caddy HTTPS optionnel, sauvegarde, diagnostic IA et rotation sécurisée des clés.

## Démarrage rapide

Installation interactive :

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=fr
```

Configuration seule :

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=fr --write-only
```

Installation non interactive :

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=fr --non-interactive --activate
```

## Résumé

`main` déploie EmDash nativement sur l’hôte VPS. Pour faire cohabiter plusieurs services ou plusieurs sites EmDash sur un même serveur, un kit Docker Compose léger est également disponible sous [`docker/`](./docker/README.md) (images multi-architectures GHCR `amd64`/`arm64`, sans liaison par défaut sur les ports 80/443). L’ancien installateur conteneurisé reste archivé sur la branche `docker`.

Prise en charge (`x86_64` / `aarch64`) :

- Debian 13 (`trixie`)
- Ubuntu 24.04 LTS (`noble`) / 26.04 LTS (`resolute`)
- EL9 / EL10
- SQLite / PostgreSQL 18 (PGDG)
- file session / Valkey
- stockage local / compatible S3, Caddy + HTTPS
- EmDash `1.6.x` : `EMDASH_ENCRYPTION_KEY` (rotation en 2 étapes), bac à sable plugins `@emdash-cms/sandbox-workerd`, contrôle `emdash migrate`, `EMDASH_MIRROR_PRESET=cn`

## Commandes principales

```bash
emdashctl --lang=fr status [--json]
emdashctl --lang=fr doctor --deep --json
emdashctl --lang=fr diagnose --json --out /tmp/emdash-diag.json
emdashctl --lang=fr smoke [--json]
emdashctl --lang=fr backup [--full] [--encrypt]
emdashctl --lang=fr restore /path/to/backup.tar.gz [--with-site] [--with-secrets]
emdashctl --lang=fr upgrade app [--dry-run] [--target <version|latest>]
emdashctl --lang=fr template diff [--stat]
emdashctl --lang=fr rotate-encryption-key [--status | --dry-run | --prune-old --confirm-prune-kid <kid>]
emdashctl --lang=fr reset-db-password
```

## Périmètre vérifié et limites

- Debian 13 / Ubuntu 24.04 / Ubuntu 26.04 / EL9 / EL10 sont validés sur de vraies VM `x86_64` ; les images conteneur `ARM64` et `workerd` sont validées nativement sur GitHub Actions `ubuntu-24.04-arm`.
- Les changements de template, de plugins et de configuration de build nécessitent toujours `pnpm build`.
- `upgrade` prend actuellement en charge `app` et `caddy-config` uniquement.

Voir aussi [README.md](./README.md), [`docker/README.md`](./docker/README.md), [`COMPATIBILITY.md`](./COMPATIBILITY.md) et [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md).
