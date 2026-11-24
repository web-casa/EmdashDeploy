# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | **日本語** | [한국어](./README.ko.md) | [Español](./README.es.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [Português](./README.pt.md)

Node.js 24 と systemd を使って EmDash `1.6.x` を VPS に導入・運用するためのネイティブツールキットです。

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

## 概要

`main` は VPS ホストへのネイティブ配置を提供します。同一サーバー上で複数サービスや複数 EmDash サイトを共存させたいユーザー向けに、[`docker/`](./docker/README.md) 配下に軽量な Docker Compose キット（GHCR ネイティブマルチアーキテクチャ `amd64`/`arm64` イメージ対応、デフォルトで 80/443 非占有）も同梱しています。従来のコンテナ版インストーラーは `docker` ブランチにアーカイブされています。

## 対応プラットフォーム（`x86_64` / `aarch64`）

| OS | バージョン | 備考 |
| --- | --- | --- |
| Debian | 13 (`trixie`) | ネイティブ |
| Ubuntu | 24.04 LTS (`noble`), 26.04 LTS (`resolute`) | ネイティブ |
| EL-like | 9, 10 | ネイティブ |

補足:

- Node.js 24 (`NodeSource`)、PostgreSQL 18 (`PGDG`)、セッションキャッシュは全プラットフォームで `Valkey`（systemd unit 自動検出）を使用します
- EmDash `1.6.x` 対応：`EMDASH_ENCRYPTION_KEY` 生成・2 段階ローテーション、`@emdash-cms/sandbox-workerd` プラグインサンドボックス、明示的 `emdash migrate` ゲート、`EMDASH_MIRROR_PRESET=cn`
- 検証範囲：Debian 13 / Ubuntu 24.04 / Ubuntu 26.04 / EL9 / EL10 は `x86_64` 実機 VM で検証済み、`ARM64` コンテナイメージと `workerd` は GitHub Actions `ubuntu-24.04-arm` ネイティブランナーで検証

## 主な運用コマンド

```bash
emdashctl --lang=ja status [--json]
emdashctl --lang=ja doctor --deep --json
emdashctl --lang=ja diagnose --json --out /tmp/emdash-diag.json
emdashctl --lang=ja smoke [--json]
emdashctl --lang=ja backup [--full] [--encrypt]
emdashctl --lang=ja restore /path/to/backup.tar.gz [--with-site] [--with-secrets]
emdashctl --lang=ja instances [--json]
emdashctl --lang=ja [--instance <name>] upgrade app [--dry-run] [--target <version|latest>]
emdashctl --lang=ja [--instance <name>] template diff [--stat]
emdashctl --lang=ja [--instance <name>] rotate-encryption-key [--status | --dry-run | --prune-old --confirm-prune-kid <kid>]
emdashctl --lang=ja [--instance <name>] migrate-db sqlite-to-postgres [--dry-run] [--yes]
emdashctl --lang=ja [--instance <name>] reset-db-password
emdashctl --lang=ja [--instance <name>] uninstall [--purge-data] [--drop-db] [--confirm-instance <name>]
sudo bash install.sh --update-cli
```

## 既知の制限

- テンプレート、プラグイン、ビルド時設定の変更後は `pnpm build` が必要です
- `upgrade` は現在 `app` と `caddy-config` のみ対応です
- ユーザー独自スクリプトや user crontab は自動移行されません

詳細は [README.md](./README.md)、[`docker/README.md`](./docker/README.md)、[`COMPATIBILITY.md`](./COMPATIBILITY.md)、[`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md) を参照してください。
