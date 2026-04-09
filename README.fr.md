# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Deutsch](./README.de.md) | **Français** | [Português](./README.pt.md)

Installateur VPS natif et boîte à outils d’exploitation pour EmDash avec Node.js, systemd, Caddy HTTPS optionnel, sauvegarde, restauration et contrôles de santé.

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

`main` déploie EmDash directement sur l’hôte VPS. L’ancienne version conteneurisée reste archivée sur la branche `docker`.

Prise en charge :

- Debian 13
- Ubuntu 24.04
- EL9 / EL10
- SQLite / PostgreSQL 18
- file session / Redis
- stockage local / compatible S3
- Caddy + HTTPS

## Commandes principales

```bash
emdashctl --lang=fr status
emdashctl --lang=fr doctor
emdashctl --lang=fr smoke
emdashctl --lang=fr backup
emdashctl --lang=fr restore /path/to/backup.tar.gz
emdashctl --lang=fr upgrade app
emdashctl --lang=fr reset-db-password
```

## Limites connues

- `main` ne fournit plus de déploiement Docker/Podman
- les changements de template, de plugins et de configuration de build nécessitent toujours `pnpm build`
- `upgrade` prend actuellement en charge `app` et `caddy-config` uniquement

Voir aussi [README.md](./README.md), [`COMPATIBILITY.md`](./COMPATIBILITY.md) et [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md).
