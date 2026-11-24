# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | **Português**

Instalador nativo para VPS e conjunto de ferramentas operacionais do EmDash `1.6.x` com Node.js 24, systemd, Caddy HTTPS opcional, backup, diagnóstico para IA e rotação segura de chaves.

## Início rápido

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=pt
```

Somente gerar configuração:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=pt --write-only
```

Instalação não interativa:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=pt --non-interactive --activate
```

## Resumo

`main` oferece implantação nativa no host VPS. Para hospedar vários serviços ou múltiplos sites EmDash no mesmo servidor, o kit leve Docker Compose também está disponível em [`docker/`](./docker/README.md) (imagens multiarquitetura GHCR `amd64`/`arm64`, sem ocupar as portas 80/443 por padrão). A implementação antiga em contêineres continua arquivada na branch `docker`.

Escopo suportado (`x86_64` / `aarch64`):

- Debian 13 (`trixie`)
- Ubuntu 24.04 LTS (`noble`) / 26.04 LTS (`resolute`)
- EL9 / EL10
- SQLite / PostgreSQL 18 (PGDG)
- file session / Valkey
- armazenamento local / compatível com S3, Caddy + HTTPS
- EmDash `1.6.x`: `EMDASH_ENCRYPTION_KEY` (rotação em 2 etapas), sandbox de plugins `@emdash-cms/sandbox-workerd`, verificação `emdash migrate`, `EMDASH_MIRROR_PRESET=cn`

## Comandos principais

```bash
emdashctl --lang=pt status [--json]
emdashctl --lang=pt doctor --deep --json
emdashctl --lang=pt diagnose --json --out /tmp/emdash-diag.json
emdashctl --lang=pt smoke [--json]
emdashctl --lang=pt backup [--full] [--encrypt]
emdashctl --lang=pt restore /path/to/backup.tar.gz [--with-site] [--with-secrets]
emdashctl --lang=pt upgrade app [--dry-run] [--target <version|latest>]
emdashctl --lang=pt template diff [--stat]
emdashctl --lang=pt rotate-encryption-key [--status | --dry-run | --prune-old --confirm-prune-kid <kid>]
emdashctl --lang=pt reset-db-password
```

## Escopo testado e limites

- Debian 13 / Ubuntu 24.04 / Ubuntu 26.04 / EL9 / EL10 foram validados em VMs reais `x86_64`; as imagens de contêiner `ARM64` e `workerd` são validadas nativamente no GitHub Actions `ubuntu-24.04-arm`.
- Alterações de template, plugins e configuração de build ainda exigem `pnpm build`.
- `upgrade` atualmente suporta apenas `app` e `caddy-config`.

Veja também [README.md](./README.md), [`docker/README.md`](./docker/README.md), [`COMPATIBILITY.md`](./COMPATIBILITY.md) e [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md).
