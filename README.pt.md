# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | **Português**

Instalador interativo do EmDash para VPS e conjunto de ferramentas operacionais, com Docker/Podman, Caddy HTTPS opcional, backup, restauração e verificações de saúde.

## Início rápido

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.pt.sh | sudo bash
```

Gerar apenas os arquivos:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.pt.sh | sudo bash -s -- --write-only
```

Instalação não interativa:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.pt.sh | sudo bash -s -- --non-interactive
```

Modo não interativo, SQLite:

```bash
EMDASH_INSTALL_DB_DRIVER=sqlite \
EMDASH_INSTALL_SESSION_DRIVER=file \
EMDASH_INSTALL_STORAGE_DRIVER=local \
sudo bash install-emdash.pt.sh --non-interactive --activate
```

Modo não interativo, PostgreSQL + Redis:

```bash
EMDASH_INSTALL_DB_DRIVER=postgres \
EMDASH_INSTALL_PG_PASSWORD='change-me-now' \
EMDASH_INSTALL_SESSION_DRIVER=redis \
EMDASH_INSTALL_REDIS_PASSWORD='change-me-too' \
sudo bash install-emdash.pt.sh --non-interactive --activate
```

Para a documentação completa, consulte a versão em inglês: [README.md](./README.md)

Comandos operacionais com wrapper em português:

```bash
emdashctl.pt.sh status
emdashctl.pt.sh doctor
emdashctl.pt.sh smoke
emdashctl.pt.sh logs app -f
emdashctl.pt.sh backup
emdashctl.pt.sh restore /path/to/backup.tar.gz
```
