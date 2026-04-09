# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | **Português**

Instalador nativo para VPS e conjunto de ferramentas operacionais do EmDash com Node.js, systemd, Caddy HTTPS opcional, backup, restauração e verificações de saúde.

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

`main` agora é apenas para implantação nativa no host VPS. A implementação antiga baseada em contêineres continua arquivada na branch `docker`.

Escopo suportado:

- Debian 13
- Ubuntu 24.04
- EL9 / EL10
- SQLite / PostgreSQL 18
- file session / Redis
- armazenamento local / compatível com S3
- Caddy + HTTPS

## Comandos principais

```bash
emdashctl --lang=pt status
emdashctl --lang=pt doctor
emdashctl --lang=pt smoke
emdashctl --lang=pt backup
emdashctl --lang=pt restore /path/to/backup.tar.gz
emdashctl --lang=pt upgrade app
emdashctl --lang=pt reset-db-password
```

## Limites conhecidos

- `main` não fornece mais implantação com Docker/Podman
- alterações de template, plugins e configuração de build ainda exigem `pnpm build`
- `upgrade` atualmente suporta apenas `app` e `caddy-config`

Veja também [README.md](./README.md), [`COMPATIBILITY.md`](./COMPATIBILITY.md) e [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md).
