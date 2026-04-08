# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | **日本語** | [한국어](./README.ko.md) | [Español](./README.es.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [Português](./README.pt.md)

EmDash を VPS に導入するための対話型インストーラー兼運用ツールです。Docker/Podman、任意の Caddy HTTPS、バックアップ、リストア、ヘルスチェックに対応します。

## 概要

このリポジトリは EmDash を VPS に配置し、導入後の基本運用まで扱えるようにするためのものです。

主な用途:

- 対話型インストール
- 環境変数による非対話インストール
- Debian/Ubuntu では Docker
- EL 系では Podman
- Caddy と HTTPS の任意有効化
- バックアップ、リストア、診断

## 主な機能

- インストーラー: [`install-emdash.sh`](./install-emdash.sh)
- 運用 CLI: [`emdashctl`](./emdashctl)
- Linode 実機テスト: [`linode-test.sh`](./linode-test.sh)
- SQLite / PostgreSQL 18
- file-based / Redis session
- local / S3-compatible storage
- `/data/emdash` 配下の標準レイアウト
- `/etc/emdash` 配下の設定生成

## 対応プラットフォーム

| OS | バージョン | ランタイム |
| --- | --- | --- |
| Debian | 12, 13 | Docker |
| Ubuntu | 22.04, 24.04 | Docker |
| EL-like | 8, 9, 10 | Podman |

非対応:

- SLES family
- Turso / libSQL

## クイックスタート

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=ja
```

設定ファイルのみ生成する場合:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=ja --write-only
```

## GHCR

GHCR builder イメージとデフォルト app イメージ公開用の workflow を同梱しています。

- Workflow: [`publish-ghcr-builder.yml`](./.github/workflows/publish-ghcr-builder.yml)
- Workflow: [`publish-ghcr-app.yml`](./.github/workflows/publish-ghcr-app.yml)
- Dockerfile: [`docker/base/Dockerfile`](./docker/base/Dockerfile)
- builder image: `ghcr.io/<repository_owner>/emdash-builder:node24-bookworm`
- default app image: `ghcr.io/<repository_owner>/emdash-app:starter-sqlite-file-local`

builder と app の違い:

- `builder` は再利用可能なビルド環境イメージです。
- `app` はビルド済みのランタイムイメージです。

`builder` を使うべきケース:

- VPS 上でローカルビルドしたい
- PostgreSQL、Redis、S3 互換ストレージを使う
- テンプレートを変更した、または柔軟性を優先したい

`app` を使うべきケース:

- 最速でデプロイしたい
- VPS 上でのローカルビルドを省きたい
- 公開済みのデフォルト構成 `starter + sqlite + file + local` を使う

利用例:

```bash
EMDASH_INSTALL_APP_BASE_IMAGE=ghcr.io/<owner>/emdash-builder:node24-bookworm \
sudo bash install-emdash.ja.sh --activate
```

ビルド済み app イメージの利用例:

```bash
EMDASH_INSTALL_APP_IMAGE=ghcr.io/<owner>/emdash-app:starter-sqlite-file-local \
sudo bash install-emdash.ja.sh --activate
```

推奨:

- 汎用またはカスタム構成では `APP_BASE_IMAGE` を優先してください
- デフォルトの SQLite/file/local 構成では `APP_IMAGE` を優先してください

## HTTPS

Caddy を有効にすると、インストーラーは公開 IP 検出、DNS 検証、`80/443` チェック、Caddy 導入、HTTPS 設定を行います。

EL では `firewalld`、Debian/Ubuntu では有効な `ufw` に対して自動でポート開放を行います。

## 実機テスト

```bash
cp .env.example .env
```

`.env` に以下を設定します。

```bash
linode_token=YOUR_TOKEN_HERE
```

実行:

```bash
bash linode-test.sh
```

より詳細なテスト計画は [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md) を参照してください。

運用コマンドは日本語 wrapper を使えます:

```bash
emdashctl.ja.sh status
emdashctl.ja.sh doctor
emdashctl.ja.sh smoke
emdashctl.ja.sh logs app -f
emdashctl.ja.sh backup
emdashctl.ja.sh restore /path/to/backup.tar.gz
```
