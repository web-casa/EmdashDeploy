# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | **Español** | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [Português](./README.pt.md)

Instalador nativo para VPS y conjunto de herramientas operativas para EmDash con Node.js, systemd, Caddy HTTPS opcional, copia de seguridad, restauración y comprobaciones de salud.

## Inicio rápido

Instalación interactiva:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=es
```

Solo generar configuración:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=es --write-only
```

Instalación no interactiva:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=es --non-interactive --activate
```

## Resumen

`main` instala EmDash directamente en el host VPS. La implementación anterior basada en contenedores permanece archivada en la rama `docker`.

Compatibilidad:

- Debian 13
- Ubuntu 24.04
- EL9 / EL10
- SQLite / PostgreSQL 18
- file session / Redis
- local / almacenamiento compatible con S3
- Caddy + HTTPS

## Comandos principales

```bash
emdashctl --lang=es status
emdashctl --lang=es doctor
emdashctl --lang=es smoke
emdashctl --lang=es backup
emdashctl --lang=es restore /path/to/backup.tar.gz
emdashctl --lang=es upgrade app
emdashctl --lang=es reset-db-password
```

## Límites conocidos

- `main` ya no ofrece despliegue con Docker/Podman
- los cambios de plantilla, plugins y configuración de build siguen requiriendo `pnpm build`
- `upgrade` solo admite `app` y `caddy-config`

Más detalles en [README.md](./README.md), [`COMPATIBILITY.md`](./COMPATIBILITY.md) y [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md).
