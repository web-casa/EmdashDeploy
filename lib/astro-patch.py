#!/usr/bin/env python3
"""Patch astro.config.mjs for EmDash 1.6+ managed fields.

Reads environment variables:
    SITE_DIR               - path to the site directory containing astro.config.mjs
    DB_DRIVER              - "sqlite" or "postgres"
    SESSION_DRIVER         - "file" or "redis"
    STORAGE_DRIVER         - "local" or "s3"
    ENABLE_PLUGIN_SANDBOX  - "1" or "0" (default "1")
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
enable_plugin_sandbox = os.environ.get("ENABLE_PLUGIN_SANDBOX", "1") == "1"


def detect_indent(source: str) -> str:
    match = re.search(r"export\s+default\s+defineConfig\(\{\s*\n([ \t]+)\w", source)
    if match:
        return match.group(1)
    return "\t"


def update_named_import(source: str, module: str, required: list[str]) -> str:
    pattern = rf'import\s*\{{\s*([^}}]*)\s*\}}\s*from\s*["\']{re.escape(module)}["\'];'
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
    pattern = r'import\s+emdash,\s*\{\s*([^}]*)\s*\}\s*from\s*["\']emdash/astro["\'];'
    match = re.search(pattern, source)
    if not match:
        raise SystemExit(f"missing emdash/astro import in {path}")
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
    pattern = r'import\s*\{\s*([^}]*)\s*\}\s*from\s*["\']emdash/db["\'];'
    match = re.search(pattern, source)
    if not match:
        raise SystemExit(f"missing emdash/db import in {path}")
    replacement = f'import {{ {required} }} from "emdash/db";'
    return source[:match.start()] + replacement + source[match.end():]


def replace_session_block(source: str, indent: str) -> str:
    # Remove any previously managed redis session block regardless of tab/space indent.
    source = re.sub(
        r'\n[ \t]+session:\s*\{\s*\n[ \t]+driver:\s*sessionDrivers\.redis\(\{\s*\n[ \t]+url:\s*process\.env\.REDIS_URL,?\s*\n[ \t]+\}\),?\s*\n[ \t]+\},?\n',
        "\n",
        source,
        count=1,
    )
    if session_driver != "redis":
        return source

    adapter_pattern = re.compile(
        r'([ \t]+adapter:\s*node\(\{\s*\n[ \t]+mode:\s*["\']standalone["\'],?\s*\n[ \t]+\}\),?\n)'
    )
    match = adapter_pattern.search(source)
    if not match:
        raise SystemExit(f"cannot find adapter block in {path}")

    i1 = indent
    i2 = indent * 2
    i3 = indent * 3
    session_block = (
        f"{i1}session: {{\n"
        f"{i2}driver: sessionDrivers.redis({{\n"
        f"{i3}url: process.env.REDIS_URL,\n"
        f"{i2}}}),\n"
        f"{i1}}},\n"
    )
    return source[:match.end()] + session_block + source[match.end():]


def find_emdash_call_span(source: str) -> tuple[int, int, str]:
    start_match = re.search(r"([ \t]*)emdash\(\{\s*\n", source)
    if not start_match:
        raise SystemExit(f"cannot find emdash config block in {path}")
    call_indent = start_match.group(1)
    brace_open = source.index("{", start_match.start())
    depth = 0
    in_str: str | None = None
    escaped = False
    i = brace_open
    while i < len(source):
        ch = source[i]
        if in_str:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == in_str:
                in_str = None
        else:
            if ch in ("'", '"', "`"):
                in_str = ch
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    # Expect closing ')' immediately after '}'
                    close_paren = source.find(")", i + 1)
                    if close_paren == -1:
                        raise SystemExit(f"unterminated emdash() call in {path}")
                    return start_match.start(), close_paren + 1, call_indent
        i += 1
    raise SystemExit(f"unterminated emdash({{ ... }}) block in {path}")


def strip_managed_field(body: str, field_name: str) -> str:
    """Remove a single-line or nested-brace property inside emdash({...})."""
    # Single-line property (e.g., siteUrl: ..., sandboxRunner: ..., database: sqlite({ url: "..." }),)
    lines = body.splitlines(keepends=True)
    out: list[str] = []
    idx = 0
    prop_re = re.compile(rf"^[ \t]+{re.escape(field_name)}\s*:")
    while idx < len(lines):
        line = lines[idx]
        if prop_re.match(line):
            # Track brace/paren balance until property terminates.
            depth = 0
            in_str: str | None = None
            escaped = False
            while idx < len(lines):
                cur = lines[idx]
                for ch in cur:
                    if in_str:
                        if escaped:
                            escaped = False
                        elif ch == "\\":
                            escaped = True
                        elif ch == in_str:
                            in_str = None
                    else:
                        if ch in ("'", '"', "`"):
                            in_str = ch
                        elif ch in "({[":
                            depth += 1
                        elif ch in ")}]":
                            depth -= 1
                idx += 1
                if depth <= 0:
                    break
            continue
        out.append(line)
        idx += 1
    return "".join(out)


def replace_emdash_block(source: str, indent: str) -> str:
    start, end, call_indent = find_emdash_call_span(source)
    block = source[start:end]
    first_nl = block.index("\n")
    last_brace = block.rindex("}")
    body = block[first_nl + 1:last_brace]
    # Remove trailing indent line before closing brace
    body = re.sub(r"[ \t]*$", "", body)

    for managed in ("siteUrl", "sandboxRunner", "database", "storage"):
        body = strip_managed_field(body, managed)
    body = body.strip("\n")

    prop_indent = call_indent + indent
    inner_indent = prop_indent + indent

    if db_driver == "postgres":
        db_block = (
            f"{prop_indent}database: postgres({{\n"
            f"{inner_indent}host: process.env.POSTGRES_HOST,\n"
            f'{inner_indent}port: Number(process.env.POSTGRES_PORT || "5432"),\n'
            f"{inner_indent}database: process.env.PG_DB_NAME,\n"
            f"{inner_indent}user: process.env.PG_DB_USER,\n"
            f"{inner_indent}password: process.env.PG_DB_PASSWORD,\n"
            f"{prop_indent}}}),\n"
        )
    else:
        db_block = (
            f"{prop_indent}database: sqlite({{\n"
            f"{inner_indent}url: `file:${{process.env.SQLITE_PATH}}`,\n"
            f"{prop_indent}}}),\n"
        )

    if storage_driver == "s3":
        storage_block = (
            f"{prop_indent}storage: s3({{\n"
            f"{inner_indent}endpoint: process.env.S3_ENDPOINT,\n"
            f"{inner_indent}region: process.env.S3_REGION,\n"
            f"{inner_indent}bucket: process.env.S3_BUCKET,\n"
            f"{inner_indent}accessKeyId: process.env.S3_ACCESS_KEY_ID,\n"
            f"{inner_indent}secretAccessKey: process.env.S3_SECRET_ACCESS_KEY,\n"
            f"{inner_indent}publicUrl: process.env.S3_PUBLIC_URL || undefined,\n"
            f"{prop_indent}}}),\n"
        )
    else:
        storage_block = (
            f"{prop_indent}storage: local({{\n"
            f"{inner_indent}directory: process.env.UPLOADS_DIR,\n"
            f'{inner_indent}baseUrl: "/_emdash/api/media/file",\n'
            f"{prop_indent}}}),\n"
        )

    site_url_line = f"{prop_indent}siteUrl: process.env.EMDASH_SITE_URL || process.env.SITE_URL || undefined,\n"
    sandbox_line = (
        f'{prop_indent}sandboxRunner: "@emdash-cms/sandbox-workerd/sandbox",\n'
        if enable_plugin_sandbox
        else ""
    )

    new_body = site_url_line + sandbox_line + db_block + storage_block
    if body:
        new_body += body + "\n"

    replacement = f"{call_indent}emdash({{\n{new_body}{call_indent}}})"
    return source[:start] + replacement + source[end:]


indent_unit = detect_indent(text)
text = update_named_import(
    text,
    "astro/config",
    ["defineConfig"] + (["sessionDrivers"] if session_driver == "redis" else []),
)
text = update_emdash_import(text)
text = update_db_import(text)
text = replace_session_block(text, indent_unit)
text = replace_emdash_block(text, indent_unit)

path.write_text(text)
