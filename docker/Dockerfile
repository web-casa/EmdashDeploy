# syntax=docker/dockerfile:1.7
FROM node:24-bookworm-slim

ARG EMDASH_TEMPLATE=blog
ARG EMDASH_TEMPLATES_REPO=https://github.com/emdash-cms/templates.git
ARG EMDASH_TEMPLATES_REF=main
ARG DB_DRIVER=sqlite
ARG SESSION_DRIVER=file
ARG STORAGE_DRIVER=local
ARG ENABLE_PLUGIN_SANDBOX=1
ARG NPM_CONFIG_REGISTRY=
ARG COREPACK_NPM_REGISTRY=
ARG EMDASH_FAST_FAIL_GOOGLE_FONTS=0
ARG APP_NODE_MAX_OLD_SPACE_SIZE=1536

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=3000 \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    NODE_OPTIONS="--max-old-space-size=${APP_NODE_MAX_OLD_SPACE_SIZE}" \
    DB_DRIVER="${DB_DRIVER}" \
    SESSION_DRIVER="${SESSION_DRIVER}" \
    STORAGE_DRIVER="${STORAGE_DRIVER}" \
    ENABLE_PLUGIN_SANDBOX="${ENABLE_PLUGIN_SANDBOX}" \
    SQLITE_PATH=/data/sqlite/data.db \
    UPLOADS_DIR=/data/uploads \
    SESSIONS_DIR=/data/sessions \
    EMDASH_AUTO_MIGRATE=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gosu \
        g++ \
        make \
        python3 \
        tini \
    && rm -rf /var/lib/apt/lists/*

# Ensure dedicated non-root user (alignable at runtime via PUID/PGID)
RUN groupadd -g 10001 emdash || true \
    && useradd -m -u 10001 -g 10001 -s /bin/bash emdash || true

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

WORKDIR /opt/emdash
COPY lib/site-common.sh lib/astro-patch.py lib/fast-fail-google-fonts.mjs /opt/emdash/lib/

# Fetch upstream EmDash template, apply shared EmDash 1.6+ config patch, and build
RUN case " ${EMDASH_TEMPLATE} " in \
        " blog " | " marketing " | " portfolio ") ;; \
        *) echo "Unsupported EMDASH_TEMPLATE: ${EMDASH_TEMPLATE}" >&2; exit 1 ;; \
    esac \
    && if [[ -n "${NPM_CONFIG_REGISTRY}" ]]; then export NPM_CONFIG_REGISTRY npm_config_registry="${NPM_CONFIG_REGISTRY}"; fi \
    && if [[ -n "${COREPACK_NPM_REGISTRY}" ]]; then export COREPACK_NPM_REGISTRY; fi \
    && if [[ "${EMDASH_FAST_FAIL_GOOGLE_FONTS}" == "1" && -z "${HTTPS_PROXY:-}${https_proxy:-}${ALL_PROXY:-}${all_proxy:-}" ]]; then \
        export EMDASH_FAST_FAIL_GOOGLE_FONTS=1; \
        export NODE_OPTIONS="${NODE_OPTIONS} --import /opt/emdash/lib/fast-fail-google-fonts.mjs"; \
    fi \
    && git clone --depth 1 --branch "${EMDASH_TEMPLATES_REF}" "${EMDASH_TEMPLATES_REPO}" /tmp/emdash-templates \
    && mkdir -p /app/site /data/sqlite /data/uploads /data/sessions \
    && cp -a "/tmp/emdash-templates/${EMDASH_TEMPLATE}/." /app/site/ \
    && rm -rf /tmp/emdash-templates \
    && source /opt/emdash/lib/site-common.sh \
    && export ROOT_DIR=/opt/emdash SITE_DIR=/app/site PROJECT_NAME="emdash-${EMDASH_TEMPLATE}" \
    && patch_site_package_json_common /app/site "emdash-${EMDASH_TEMPLATE}" "${DB_DRIVER}" "${SESSION_DRIVER}" "${STORAGE_DRIVER}" "${ENABLE_PLUGIN_SANDBOX}" \
    && render_site_astro_config_common \
    && render_site_health_endpoint_common \
    && ensure_site_pnpm /app/site \
    && cd /app/site \
    && REG_ARG=() \
    && if [[ -n "${NPM_CONFIG_REGISTRY}" ]]; then REG_ARG+=(--registry="${NPM_CONFIG_REGISTRY}"); fi \
    && pnpm install --no-frozen-lockfile "${REG_ARG[@]}" \
    && pnpm build \
    && chown -R 10001:10001 /app /data

COPY docker/entrypoint.sh /usr/local/bin/emdash-entrypoint.sh
RUN chmod 0755 /usr/local/bin/emdash-entrypoint.sh

WORKDIR /app/site
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
    CMD curl -fsS http://127.0.0.1:${PORT:-3000}/healthz >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/emdash-entrypoint.sh"]
CMD ["start"]
