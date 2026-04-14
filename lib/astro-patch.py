#!/usr/bin/env python3
"""Patch astro.config.mjs for EmDash managed fields.

Reads environment variables:
    SITE_DIR        - path to the site directory containing astro.config.mjs
    DB_DRIVER       - "sqlite" or "postgres"
    SESSION_DRIVER  - "file" or "redis"
    STORAGE_DRIVER  - "local" or "s3"
"""

import os
import re
from pathlib import Path

site_dir = Path(os.environ["SITE_DIR"])
path = site_dir / "astro.config.mjs"
text = path.read_text()

db_driver = os.environ["DB_DRIVER"]
session_driver = os.environ["SESSION_DRIVER"]
storage_driver = os.environ["STORAGE_DRIVER"]


def update_named_import(source: str, module: str, required: list[str]) -> str:
    pattern = rf'import\s*\{{\s*([^}}]*)\s*\}}\s*from\s*"{re.escape(module)}";'
    match = re.search(pattern, source)
    if not match:
        raise SystemExit(f"missing import for {module} in {path}")
    names = [item.strip() for item in match.group(1).split(",") if item.strip()]
    merged: list[str] = []
    for name in names + required:
        if name not in merged:
            merged.append(name)
    if module == "astro/config" and session_driver != "redis":
        merged = [name for name in merged if name != "sessionDrivers"]
    replacement = f'import {{ {", ".join(merged)} }} from "{module}";'
    return source[:match.start()] + replacement + source[match.end():]


def update_emdash_import(source: str) -> str:
    pattern = r'import\s+emdash,\s*\{\s*([^}]*)\s*\}\s*from\s*"emdash/astro";'
    match = re.search(pattern, source)
    if not match:
        raise SystemExit(f'missing emdash/astro import in {path}')
    names = [item.strip() for item in match.group(1).split(",") if item.strip()]
    required = ["local"]
    if storage_driver == "s3":
        required.append("s3")
    merged: list[str] = []
    for name in names + required:
        if name not in merged:
            merged.append(name)
    replacement = f'import emdash, {{ {", ".join(merged)} }} from "emdash/astro";'
    return source[:match.start()] + replacement + source[match.end():]


def update_db_import(source: str) -> str:
    required = "postgres" if db_driver == "postgres" else "sqlite"
    pattern = r'import\s*\{\s*([^}]*)\s*\}\s*from\s*"emdash/db";'
    match = re.search(pattern, source)
    if not match:
        raise SystemExit(f'missing emdash/db import in {path}')
    replacement = f'import {{ {required} }} from "emdash/db";'
    return source[:match.start()] + replacement + source[match.end():]


def replace_session_block(source: str) -> str:
    source = re.sub(
        r'\n\tsession:\s*\{\n\t\tdriver: sessionDrivers\.redis\(\{\n\t\t\turl: process\.env\.REDIS_URL,\n\t\t\}\),\n\t\},\n',
        '\n',
        source,
        count=1,
    )
    if session_driver != "redis":
        return source
    adapter_block = '\tadapter: node({\n\t\tmode: "standalone",\n\t}),\n'
    session_block = (
        '\tsession: {\n'
        '\t\tdriver: sessionDrivers.redis({\n'
        '\t\t\turl: process.env.REDIS_URL,\n'
        '\t\t}),\n'
        '\t},\n'
    )
    if adapter_block not in source:
        raise SystemExit(f'cannot find adapter block in {path}')
    return source.replace(adapter_block, adapter_block + session_block, 1)


def replace_emdash_block(source: str) -> str:
    pattern = r'emdash\(\{\n(?P<body>[\s\S]*?)\n\t\t\}\)'
    match = re.search(pattern, source)
    if not match:
        raise SystemExit(f'cannot find emdash config block in {path}')
    body = match.group("body")
    body = re.sub(r'^\t\t\tsiteUrl:.*\n', '', body, flags=re.MULTILINE)
    body = re.sub(
        r'^\t\t\tdatabase:\s*(?:sqlite|postgres)\(\{[\s\S]*?\n\t\t\t\}\),\n?',
        '',
        body,
        flags=re.MULTILINE,
    )
    body = re.sub(
        r'^\t\t\tstorage:\s*(?:local|s3)\(\{[\s\S]*?\n\t\t\t\}\),\n?',
        '',
        body,
        flags=re.MULTILINE,
    )
    body = body.lstrip("\n")

    if db_driver == "postgres":
        db_block = (
            '\t\t\tdatabase: postgres({\n'
            '\t\t\t\thost: process.env.POSTGRES_HOST,\n'
            '\t\t\t\tport: Number(process.env.POSTGRES_PORT || "5432"),\n'
            '\t\t\t\tdatabase: process.env.PG_DB_NAME,\n'
            '\t\t\t\tuser: process.env.PG_DB_USER,\n'
            '\t\t\t\tpassword: process.env.PG_DB_PASSWORD,\n'
            '\t\t\t}),\n'
        )
    else:
        db_block = (
            '\t\t\tdatabase: sqlite({\n'
            '\t\t\t\turl: `file:${process.env.SQLITE_PATH}`,\n'
            '\t\t\t}),\n'
        )

    if storage_driver == "s3":
        storage_block = (
            '\t\t\tstorage: s3({\n'
            '\t\t\t\tendpoint: process.env.S3_ENDPOINT,\n'
            '\t\t\t\tregion: process.env.S3_REGION,\n'
            '\t\t\t\tbucket: process.env.S3_BUCKET,\n'
            '\t\t\t\taccessKeyId: process.env.S3_ACCESS_KEY_ID,\n'
            '\t\t\t\tsecretAccessKey: process.env.S3_SECRET_ACCESS_KEY,\n'
            '\t\t\t\tpublicUrl: process.env.S3_PUBLIC_URL || undefined,\n'
            '\t\t\t}),\n'
        )
    else:
        storage_block = (
            '\t\t\tstorage: local({\n'
            '\t\t\t\tdirectory: process.env.UPLOADS_DIR,\n'
            '\t\t\t\tbaseUrl: "/_emdash/api/media/file",\n'
            '\t\t\t}),\n'
        )

    site_url_line = '\t\t\tsiteUrl: process.env.EMDASH_SITE_URL || process.env.SITE_URL || undefined,\n'
    new_body = site_url_line + db_block + storage_block + body
    replacement = f'emdash({{\n{new_body}\n\t\t}})'
    return source[:match.start()] + replacement + source[match.end():]


text = update_named_import(text, "astro/config", ["defineConfig"] + (["sessionDrivers"] if session_driver == "redis" else []))
text = update_emdash_import(text)
text = update_db_import(text)
text = replace_session_block(text)
text = replace_emdash_block(text)

path.write_text(text)
