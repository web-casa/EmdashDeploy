#!/usr/bin/env python3
"""
Zero-dependency SQLite -> PostgreSQL data migrator for EmDash 1.6.x.

Design principles:
- Relies on upstream `pnpm exec emdash migrate` having already created the exact
  PostgreSQL schema and `_emdash_migrations` history in the target database.
- Uses standard library `sqlite3` + `psql` CLI (no psycopg2 dependency required).
- Works under standard non-superuser PostgreSQL roles by ordering table inserts
  topologically according to PostgreSQL foreign-key constraints.
- Converts SQLite dynamic values accurately using PostgreSQL `information_schema.columns`
  types (boolean, bytea, json/jsonb, numeric, text/encrypted envelopes), resets
  PostgreSQL serial/identity sequences, and verifies exact per-table row counts.
"""

import argparse
import json
import os
import sqlite3
import subprocess
import sys
from collections import defaultdict, deque


def run_psql(pg_env, args_list, sql_input=None):
    cmd = [
        "psql",
        "-h", pg_env["host"],
        "-p", str(pg_env["port"]),
        "-U", pg_env["user"],
        "-d", pg_env["dbname"],
        "-v", "ON_ERROR_STOP=1",
        *args_list,
    ]
    env = os.environ.copy()
    env["PGPASSWORD"] = pg_env["password"]
    proc = subprocess.run(
        cmd,
        input=sql_input,
        text=True,
        capture_output=True,
        env=env,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"psql failed (rc={proc.returncode}): {proc.stderr.strip()}")
    return proc.stdout


def pg_ident(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


def pg_literal(val, data_type: str, udt_name: str) -> str:
    if val is None:
        return "NULL"

    dt = (data_type or "").lower()
    udt = (udt_name or "").lower()

    if dt == "boolean" or udt == "bool":
        if isinstance(val, bool):
            return "TRUE" if val else "FALSE"
        if isinstance(val, (int, float)):
            return "TRUE" if val != 0 else "FALSE"
        s = str(val).strip().lower()
        if s in ("1", "true", "t", "yes"):
            return "TRUE"
        if s in ("0", "false", "f", "no"):
            return "FALSE"
        raise ValueError(f"Cannot coerce value {val!r} to PostgreSQL boolean")

    if dt == "bytea" or udt == "bytea":
        if isinstance(val, memoryview):
            raw = val.tobytes()
        elif isinstance(val, bytes):
            raw = val
        else:
            raw = str(val).encode("utf-8")
        return f"decode('{raw.hex()}', 'hex')"

    if dt in ("smallint", "integer", "bigint", "real", "double precision", "numeric", "decimal"):
        if isinstance(val, bool):
            return "1" if val else "0"
        if isinstance(val, (int, float)):
            return str(val)
        s = str(val).strip()
        if s == "":
            return "NULL"
        return s

    if dt in ("json", "jsonb") or udt in ("json", "jsonb"):
        if isinstance(val, (dict, list)):
            raw = json.dumps(val, ensure_ascii=False)
        else:
            raw = str(val)
        escaped = raw.replace("'", "''")
        cast = "::jsonb" if (dt == "jsonb" or udt == "jsonb") else "::json"
        return f"'{escaped}'{cast}"

    # Default text / varchar / timestamp / uuid / etc. (preserves encrypted JSON envelopes verbatim)
    if isinstance(val, bytes):
        text = val.decode("utf-8", errors="replace")
    else:
        text = str(val)
    return "'" + text.replace("'", "''") + "'"


def fetch_pg_schema(pg_env):
    cols_out = run_psql(
        pg_env,
        ["-tA", "-F", "\t", "-c", """
            SELECT table_name, column_name, data_type, udt_name
            FROM information_schema.columns
            WHERE table_schema = 'public'
            ORDER BY table_name, ordinal_position;
        """],
    )
    pg_tables = {}
    for line in cols_out.splitlines():
        if not line.strip():
            continue
        tbl, col, dt, udt = line.split("\t")
        pg_tables.setdefault(tbl, {})[col] = (dt, udt)

    fk_out = run_psql(
        pg_env,
        ["-tA", "-F", "\t", "-c", """
            SELECT DISTINCT tc.table_name AS child_table, ccu.table_name AS parent_table
            FROM information_schema.table_constraints AS tc
            JOIN information_schema.constraint_column_usage AS ccu
              ON ccu.constraint_name = tc.constraint_name
             AND ccu.table_schema = tc.table_schema
            WHERE tc.constraint_type = 'FOREIGN KEY'
              AND tc.table_schema = 'public'
              AND tc.table_name <> ccu.table_name;
        """],
    )
    fk_deps = defaultdict(set)
    for line in fk_out.splitlines():
        if not line.strip():
            continue
        child, parent = line.split("\t")
        fk_deps[child].add(parent)

    return pg_tables, fk_deps


def topo_sort_tables(tables, fk_deps):
    table_set = set(tables)
    in_degree = {t: 0 for t in tables}
    children = defaultdict(list)

    for child in tables:
        for parent in fk_deps.get(child, set()):
            if parent in table_set:
                children[parent].append(child)
                in_degree[child] += 1

    queue = deque(sorted([t for t, deg in in_degree.items() if deg == 0]))
    ordered = []
    while queue:
        node = queue.popleft()
        ordered.append(node)
        for nxt in sorted(children[node]):
            in_degree[nxt] -= 1
            if in_degree[nxt] == 0:
                queue.append(nxt)

    # Append any cycle participants deterministically
    for t in sorted(tables):
        if t not in ordered:
            ordered.append(t)
    return ordered


def fetch_sqlite_tables(sqlite_path: str):
    conn = sqlite3.connect(f"file:{sqlite_path}?mode=ro", uri=True)
    cur = conn.cursor()
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;")
    tables = [r[0] for r in cur.fetchall()]
    info = {}
    for tbl in tables:
        cur.execute(f"PRAGMA table_info({pg_ident(tbl)});")
        cols = [r[1] for r in cur.fetchall()]
        cnt = cur.execute(f"SELECT COUNT(*) FROM {pg_ident(tbl)};").fetchone()[0]
        info[tbl] = {"columns": cols, "count": cnt}
    conn.close()
    return info


MIGRATION_META_TABLES = {
    "_emdash_migrations",
    "__drizzle_migrations",
    "emdash_migrations",
}


def check_pg_target_empty(pg_env, pg_tables):
    non_empty = {}
    for tbl in sorted(pg_tables.keys()):
        if tbl in MIGRATION_META_TABLES:
            continue
        cnt = int(run_psql(pg_env, ["-tAc", f"SELECT COUNT(*) FROM {pg_ident(tbl)};"]).strip() or "0")
        if cnt > 0:
            non_empty[tbl] = cnt
    return non_empty


def build_migration_sql(sqlite_path: str, ordered_tables, sqlite_info, pg_tables, truncate_target: bool):
    conn = sqlite3.connect(f"file:{sqlite_path}?mode=ro", uri=True)
    cur = conn.cursor()

    lines = ["BEGIN;", "SET CONSTRAINTS ALL DEFERRED;"]
    if truncate_target and ordered_tables:
        trunc_list = ", ".join(pg_ident(t) for t in reversed(ordered_tables))
        lines.append(f"TRUNCATE TABLE {trunc_list} RESTART IDENTITY CASCADE;")

    migrated_counts = {}
    for tbl in ordered_tables:
        pg_cols = pg_tables[tbl]
        common_cols = [c for c in sqlite_info[tbl]["columns"] if c in pg_cols]
        if not common_cols:
            migrated_counts[tbl] = 0
            continue

        select_cols = ", ".join(pg_ident(c) for c in common_cols)
        insert_cols = ", ".join(pg_ident(c) for c in common_cols)
        rows = cur.execute(f"SELECT {select_cols} FROM {pg_ident(tbl)};").fetchall()
        migrated_counts[tbl] = len(rows)

        if not rows:
            continue

        # Batch inserts in chunks of 100 for speed while keeping SQL readable
        chunk_size = 100
        for idx in range(0, len(rows), chunk_size):
            batch = rows[idx:idx + chunk_size]
            val_tuples = []
            for row in batch:
                literals = [
                    pg_literal(v, pg_cols[c][0], pg_cols[c][1])
                    for v, c in zip(row, common_cols)
                ]
                val_tuples.append("(" + ", ".join(literals) + ")")
            lines.append(
                f"INSERT INTO {pg_ident(tbl)} ({insert_cols}) VALUES\n  "
                + ",\n  ".join(val_tuples)
                + ";"
            )

        # Reset PostgreSQL serial / identity sequences on integer columns
        for c in common_cols:
            dt = pg_cols[c][0].lower()
            if dt in ("smallint", "integer", "bigint"):
                q_tbl = tbl.replace("'", "''")
                q_col = c.replace("'", "''")
                lines.append(
                    f"DO $$ DECLARE seq text; maxv bigint; BEGIN "
                    f"seq := pg_get_serial_sequence('public.{q_tbl}', '{q_col}'); "
                    f"IF seq IS NOT NULL THEN "
                    f"SELECT MAX({pg_ident(c)}) INTO maxv FROM {pg_ident(tbl)}; "
                    f"IF maxv IS NOT NULL THEN PERFORM setval(seq, maxv, true); END IF; "
                    f"END IF; END $$;"
                )

    lines.append("COMMIT;")
    conn.close()
    return "\n".join(lines) + "\n", migrated_counts


def main():
    parser = argparse.ArgumentParser(description="Migrate EmDash data from SQLite to PostgreSQL")
    parser.add_argument("--sqlite-path", required=True)
    parser.add_argument("--pg-host", default="127.0.0.1")
    parser.add_argument("--pg-port", default="5432")
    parser.add_argument("--pg-user", required=True)
    parser.add_argument("--pg-db", required=True)
    parser.add_argument("--check-target-empty", action="store_true")
    parser.add_argument("--truncate-target", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    pg_env = {
        "host": args.pg_host,
        "port": args.pg_port,
        "user": args.pg_user,
        "dbname": args.pg_db,
        "password": os.environ.get("PGPASSWORD", ""),
    }

    sqlite_info = fetch_sqlite_tables(args.sqlite_path)
    pg_tables, fk_deps = fetch_pg_schema(pg_env)

    if args.check_target_empty:
        non_empty = check_pg_target_empty(pg_env, pg_tables)
        print(json.dumps({"non_empty_tables": non_empty}, indent=2))
        sys.exit(0 if not non_empty else 2)

    skip_tables = set(MIGRATION_META_TABLES)
    missing_in_pg = [t for t in sqlite_info if t not in pg_tables and t not in skip_tables]
    common_tables = [t for t in sqlite_info if t in pg_tables and t not in skip_tables]
    ordered = topo_sort_tables(common_tables, fk_deps)

    if args.dry_run:
        plan = {
            "tables_to_migrate": [
                {"table": t, "rows": sqlite_info[t]["count"]} for t in ordered
            ],
            "skipped_tables": sorted(skip_tables & set(sqlite_info.keys())),
            "missing_in_pg": missing_in_pg,
        }
        print(json.dumps(plan, indent=2))
        return

    if missing_in_pg:
        sys.stderr.write(f"[WARN] SQLite tables not found in PostgreSQL schema (skipped): {', '.join(missing_in_pg)}\n")

    non_meta_sqlite = [t for t in sqlite_info if t not in skip_tables]
    if non_meta_sqlite and not ordered:
        raise SystemExit(
            f"Target PostgreSQL database has 0 matching tables for {len(non_meta_sqlite)} SQLite tables. "
            "Ensure PostgreSQL schema was initialized via `emdash migrate` before data migration."
        )

    missing_non_empty = {t: sqlite_info[t]["count"] for t in missing_in_pg if sqlite_info[t]["count"] > 0}
    if missing_non_empty:
        raise SystemExit(
            f"Refusing silent data loss: non-empty SQLite tables are missing in PostgreSQL schema: {json.dumps(missing_non_empty)}"
        )

    if not args.truncate_target:
        non_empty = check_pg_target_empty(pg_env, {t: pg_tables[t] for t in ordered})
        if non_empty:
            raise SystemExit(
                f"Target PostgreSQL database is not empty ({non_empty}). "
                "Refusing to overwrite without --truncate-target."
            )

    sql_payload, expected_counts = build_migration_sql(
        args.sqlite_path, ordered, sqlite_info, pg_tables, args.truncate_target
    )
    run_psql(pg_env, [], sql_input=sql_payload)

    # Exact per-table row count verification
    mismatches = {}
    verified = {}
    for tbl in ordered:
        pg_cnt = int(run_psql(pg_env, ["-tAc", f"SELECT COUNT(*) FROM {pg_ident(tbl)};"]).strip() or "0")
        exp = expected_counts.get(tbl, 0)
        verified[tbl] = pg_cnt
        if pg_cnt != exp:
            mismatches[tbl] = {"sqlite": exp, "postgres": pg_cnt}

    if mismatches:
        raise SystemExit(f"Row count verification failed after migration: {json.dumps(mismatches)}")

    print(json.dumps({
        "status": "ok",
        "migrated_tables": len(ordered),
        "total_rows": sum(verified.values()),
        "counts": verified,
        "missing_in_pg": missing_in_pg,
    }, indent=2))


if __name__ == "__main__":
    main()
