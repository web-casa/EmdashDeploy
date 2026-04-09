# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | **日本語** | [한국어](./README.ko.md) | [Español](./README.es.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [Português](./README.pt.md)

Node.js と systemd を使って EmDash を VPS に直接導入するためのネイティブ運用ツールです。

## クイックスタート

対話型インストール:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=ja
```

設定ファイルのみ生成:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=ja --write-only
```

非対話インストール:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=ja --non-interactive --activate
```

ローカル checkout:

```bash
git clone https://github.com/web-casa/EmdashDeploy.git
cd EmdashDeploy
chmod +x bootstrap.sh install.sh emdashctl linode-test.sh
sudo bash install.sh --lang=ja --activate
```

統一エントリポイント:

- `bootstrap.sh --lang=<code>`
- `install.sh --lang=<code>`
- `emdashctl --lang=<code>`

## 概要

このリポジトリは EmDash を VPS ホストにネイティブ配置します。Docker/Podman は `main` では使いません。

対応する内容:

- 対話型インストール
- 環境変数による非対話インストール
- Node.js + systemd によるネイティブ運用
- Caddy + HTTPS
- SQLite / PostgreSQL 18
- file session / Redis
- local / S3-compatible storage
- backup / restore / health check / upgrade

従来のコンテナ版は `docker` ブランチにアーカイブされています。

## 対応プラットフォーム

| OS | バージョン | 備考 |
| --- | --- | --- |
| Debian | 13 | ネイティブ |
| Ubuntu | 24.04 | ネイティブ |
| EL-like | 9, 10 | ネイティブ |

補足:

- Node.js は `NodeSource`
- PostgreSQL 18 は `PGDG`
- Redis はシステムパッケージ
- EL10 では `valkey` に自動対応

## 主な機能

- インストーラー: [`install.sh`](./install.sh)
- 運用 CLI: [`emdashctl`](./emdashctl)
- Linode 実機テスト: [`linode-test.sh`](./linode-test.sh)
- ネイティブ `systemd` サービス
- ネイティブ Caddy
- SQLite / PostgreSQL 18
- file / Redis session
- local / S3-compatible storage
- S3 backup

## 非対話インストール例

```bash
EMDASH_INSTALL_DB_DRIVER=sqlite \
EMDASH_INSTALL_SESSION_DRIVER=file \
EMDASH_INSTALL_STORAGE_DRIVER=local \
sudo bash install.sh --lang=ja --non-interactive --activate
```

```bash
EMDASH_INSTALL_DB_DRIVER=postgres \
EMDASH_INSTALL_PG_PASSWORD='change-me-now' \
EMDASH_INSTALL_SESSION_DRIVER=redis \
EMDASH_INSTALL_REDIS_PASSWORD='change-me-too' \
sudo bash install.sh --lang=ja --non-interactive --activate
```

## 主な運用コマンド

```bash
emdashctl --lang=ja status
emdashctl --lang=ja doctor
emdashctl --lang=ja smoke
emdashctl --lang=ja backup
emdashctl --lang=ja restore /path/to/backup.tar.gz
emdashctl --lang=ja upgrade app
emdashctl --lang=ja reset-db-password
```

## `docker` ブランチからの移行

コンテナ版を使い続ける場合は `docker` ブランチを使用してください。  
`main` はネイティブ版です。

違い:

- `compose.yml` は使いません
- コンテナランタイムは不要です
- app は `systemd` で管理されます
- PostgreSQL / Redis / Caddy はホストに直接入ります

## 既知の制限

- `main` では Docker/Podman デプロイを提供しません
- 対応 OS は Debian 13、Ubuntu 24.04、EL9、EL10 に限定されます
- テンプレート、プラグイン、ビルド時設定の変更後は `pnpm build` が必要です
- `upgrade` は現在 `app` と `caddy-config` のみ対応です
- ユーザー独自スクリプト、user crontab、削除済み raw URL は自動移行されません

詳細は [`COMPATIBILITY.md`](./COMPATIBILITY.md) と [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md) を参照してください。
