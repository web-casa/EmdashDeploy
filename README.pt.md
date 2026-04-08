# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | **Português**

Instalador interativo do EmDash para VPS e conjunto de ferramentas operacionais, com Docker/Podman, Caddy HTTPS opcional, backup, restauração e verificações de saúde.

## Início rápido

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=pt
```

Gerar apenas os arquivos:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=pt --write-only
```

Instalação não interativa:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=pt --non-interactive
```

Modo não interativo, SQLite:

```bash
EMDASH_INSTALL_DB_DRIVER=sqlite \
EMDASH_INSTALL_SESSION_DRIVER=file \
EMDASH_INSTALL_STORAGE_DRIVER=local \
sudo bash install.sh --lang=pt --non-interactive --activate
```

Modo não interativo, PostgreSQL + Redis:

```bash
EMDASH_INSTALL_DB_DRIVER=postgres \
EMDASH_INSTALL_PG_PASSWORD='change-me-now' \
EMDASH_INSTALL_SESSION_DRIVER=redis \
EMDASH_INSTALL_REDIS_PASSWORD='change-me-too' \
sudo bash install.sh --lang=pt --non-interactive --activate
```

Para a documentação completa, consulte a versão em inglês: [README.md](./README.md)

Comandos operacionais com parâmetro de idioma:

```bash
emdashctl --lang=pt status
emdashctl --lang=pt doctor
emdashctl --lang=pt smoke
emdashctl --lang=pt logs app -f
emdashctl --lang=pt backup
emdashctl --lang=pt restore /path/to/backup.tar.gz
```
