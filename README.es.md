# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | **Español** | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [Português](./README.pt.md)

Instalador interactivo de EmDash para VPS y conjunto de herramientas operativas, con Docker/Podman, Caddy HTTPS opcional, copias de seguridad, restauración y comprobaciones de salud.

## Inicio rápido

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=es
```

Generar solo los archivos:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=es --write-only
```

Instalación no interactiva:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=es --non-interactive
```

Modo no interactivo, SQLite:

```bash
EMDASH_INSTALL_DB_DRIVER=sqlite \
EMDASH_INSTALL_SESSION_DRIVER=file \
EMDASH_INSTALL_STORAGE_DRIVER=local \
sudo bash install-emdash.es.sh --non-interactive --activate
```

Modo no interactivo, PostgreSQL + Redis:

```bash
EMDASH_INSTALL_DB_DRIVER=postgres \
EMDASH_INSTALL_PG_PASSWORD='change-me-now' \
EMDASH_INSTALL_SESSION_DRIVER=redis \
EMDASH_INSTALL_REDIS_PASSWORD='change-me-too' \
sudo bash install-emdash.es.sh --non-interactive --activate
```

Para la documentación completa, consulta la versión en inglés: [README.md](./README.md)

Comandos operativos con wrapper en español:

```bash
emdashctl.es.sh status
emdashctl.es.sh doctor
emdashctl.es.sh smoke
emdashctl.es.sh logs app -f
emdashctl.es.sh backup
emdashctl.es.sh restore /path/to/backup.tar.gz
```
