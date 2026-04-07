# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [日本語](./README.ja.md) | [Deutsch](./README.de.md) | **Français** | [한국어](./README.ko.md)

Installateur VPS interactif et boîte à outils d’exploitation pour EmDash, avec Docker/Podman, Caddy HTTPS optionnel, sauvegarde, restauration et contrôles de santé.

## Objectif

Ce dépôt sert à déployer EmDash sur un VPS et à fournir les commandes principales pour l’exploitation après installation.

## Fonctions principales

- Installateur : [`install-emdash.sh`](./install-emdash.sh)
- CLI d’exploitation : [`emdashctl`](./emdashctl)
- Test réel sur VPS Linode : [`linode-test.sh`](./linode-test.sh)
- SQLite ou PostgreSQL 18
- Sessions `file-based` ou Redis
- Stockage local ou S3-compatible
- Caddy natif optionnel sur l’hôte

## Plateformes prises en charge

| Système | Versions | Runtime |
| --- | --- | --- |
| Debian | 12, 13 | Docker |
| Ubuntu | 22.04, 24.04 | Docker |
| EL-like | 8, 9, 10 | Podman |

Non pris en charge :

- famille SLES
- Turso / libSQL

## Démarrage rapide

```bash
git clone https://github.com/web-casa/EmdashDeploy.git
cd EmdashDeploy
chmod +x install-emdash.sh emdashctl linode-test.sh
sudo bash install-emdash.sh
```

Activation immédiate :

```bash
sudo bash install-emdash.sh --activate
```

## GHCR

Le dépôt inclut des workflows GitHub Actions pour publier l’image builder et une image app par défaut sur GHCR.

- Workflow : [`publish-ghcr-builder.yml`](./.github/workflows/publish-ghcr-builder.yml)
- Workflow : [`publish-ghcr-app.yml`](./.github/workflows/publish-ghcr-app.yml)
- Dockerfile : [`docker/base/Dockerfile`](./docker/base/Dockerfile)
- Image builder : `ghcr.io/<repository_owner>/emdash-builder:node24-bookworm`
- Image app par défaut : `ghcr.io/<repository_owner>/emdash-app:starter-sqlite-file-local`

Différence entre `builder` et `app` :

- `builder` est une image réutilisable pour l’environnement de build.
- `app` est une image d’exécution déjà construite.

Utilisez `builder` si :

- vous voulez construire le site directement sur le VPS
- vous utilisez PostgreSQL, Redis ou un stockage compatible S3
- vous avez modifié le template ou vous voulez garder une flexibilité maximale

Utilisez `app` si :

- vous voulez le chemin de déploiement le plus rapide
- vous voulez éviter un build local de l’application sur le VPS
- vous utilisez le profil publié par défaut : `starter + sqlite + file + local`

Exemple :

```bash
EMDASH_INSTALL_APP_BASE_IMAGE=ghcr.io/<owner>/emdash-builder:node24-bookworm \
sudo bash install-emdash.sh --activate
```

Exemple avec une image app préconstruite :

```bash
EMDASH_INSTALL_APP_IMAGE=ghcr.io/<owner>/emdash-app:starter-sqlite-file-local \
sudo bash install-emdash.sh --activate
```

Recommandation :

- Pour les déploiements généraux ou personnalisés, préférez `APP_BASE_IMAGE`
- Pour le profil SQLite/file/local par défaut, préférez `APP_IMAGE`

## HTTPS

Si Caddy est activé, l’installateur détecte l’IP publique, vérifie le DNS, contrôle les ports `80/443`, installe Caddy sur l’hôte et configure HTTPS.

Sur EL, `firewalld` est configuré automatiquement. Sur Debian/Ubuntu, `ufw` est configuré automatiquement s’il est actif.

## Tests VPS

```bash
cp .env.example .env
```

Puis :

```bash
linode_token=YOUR_TOKEN_HERE
```

Lancer un test :

```bash
bash linode-test.sh
```

Voir aussi [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md).
