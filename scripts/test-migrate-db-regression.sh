#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# 1. Verify Google Fonts fast-fail Node preload hook (when Node 24+ is available)
if command -v node >/dev/null 2>&1; then
	# 1a. Enabled without proxy -> rejects fonts.google.com with AbortError in <500ms
	EMDASH_FAST_FAIL_GOOGLE_FONTS=1 HTTPS_PROXY="" https_proxy="" ALL_PROXY="" all_proxy="" \
		node --import "${SCRIPT_DIR}/lib/fast-fail-google-fonts.mjs" -e '
			const t0 = Date.now();
			fetch("https://fonts.google.com/metadata/fonts").then(
				() => { console.error("expected fast-fail rejection"); process.exit(1); },
				(err) => {
					const ms = Date.now() - t0;
					if (err.name !== "AbortError") { console.error("expected AbortError, got", err.name); process.exit(1); }
					if (ms > 500) { console.error("fast-fail too slow:", ms); process.exit(1); }
				}
			);
		'

	# 1b. Disabled (=0) -> hook must NOT wrap globalThis.fetch with fast-fail
	EMDASH_FAST_FAIL_GOOGLE_FONTS=0 \
		node --import "${SCRIPT_DIR}/lib/fast-fail-google-fonts.mjs" -e '
			if (globalThis.__emdashFastFailGoogleFontsInstalled) {
				console.error("hook should not install when EMDASH_FAST_FAIL_GOOGLE_FONTS=0");
				process.exit(1);
			}
		'

	# 1c. Enabled (=1) WITH HTTPS_PROXY -> hook must respect proxy and NOT intercept
	EMDASH_FAST_FAIL_GOOGLE_FONTS=1 HTTPS_PROXY="http://127.0.0.1:7890" \
		node --import "${SCRIPT_DIR}/lib/fast-fail-google-fonts.mjs" -e '
			if (globalThis.__emdashFastFailGoogleFontsInstalled) {
				console.error("hook should defer to HTTPS_PROXY");
				process.exit(1);
			}
		'
fi

# 2. Unit test lib/migrate-sqlite-to-pg.py (pg_literal, topo_sort_tables, build_migration_sql, CLI with mock psql)
SQLITE_DB="${TMP_DIR}/source.db"
python3 - "${SCRIPT_DIR}/lib/migrate-sqlite-to-pg.py" "${SQLITE_DB}" <<'PY'
import importlib.util, json, sqlite3, sys

spec = importlib.util.spec_from_file_location("migrator", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

# Test pg_literal coercions
assert mod.pg_literal(None, "text", "text") == "NULL"
assert mod.pg_literal(1, "boolean", "bool") == "TRUE"
assert mod.pg_literal(0, "boolean", "bool") == "FALSE"
assert mod.pg_literal(b"\xde\xad", "bytea", "bytea") == "decode('dead', 'hex')"
assert mod.pg_literal(42, "integer", "int4") == "42"
assert mod.pg_literal('{"a":1}', "jsonb", "jsonb") == "'{\"a\":1}'::jsonb"
envelope = '{"$emdash":"enc","v":1,"kid":"k1","iv":"aa","ct":"bb","tag":"cc"}'
assert mod.pg_literal(envelope, "text", "text") == f"'{envelope}'"
assert mod.pg_literal("O'Reilly", "text", "text") == "'O''Reilly'"

# Test topological sort on FK chain: users <- posts <- comments, independent tags
ordered = mod.topo_sort_tables(
    ["comments", "posts", "users", "tags"],
    {"posts": {"users"}, "comments": {"posts", "users"}},
)
assert ordered.index("users") < ordered.index("posts") < ordered.index("comments"), ordered

# Build real SQLite DB (including SQLite-only _emdash_fts_* shadow table & dynamic ec_posts collection table)
conn = sqlite3.connect(sys.argv[2])
conn.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT, is_admin INTEGER, secret TEXT)")
conn.execute("CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INTEGER, meta TEXT)")
conn.execute("CREATE TABLE _emdash_fts_posts_config (k TEXT PRIMARY KEY, v TEXT)")
conn.execute("CREATE TABLE ec_posts (id TEXT PRIMARY KEY, slug TEXT, status TEXT DEFAULT 'draft', version INTEGER DEFAULT 1, locale TEXT NOT NULL DEFAULT 'en')")
conn.execute("INSERT INTO users VALUES (1, 'a@b.com', 1, ?)", (envelope,))
conn.execute("INSERT INTO posts VALUES (10, 1, '{\"views\":5}')")
conn.execute("INSERT INTO _emdash_fts_posts_config VALUES ('version', '4')")
conn.execute("INSERT INTO ec_posts VALUES ('p1', 'hello-world', 'published', 1, 'en')")
conn.commit()
conn.close()

# Verify FTS5 shadow table detection & dynamic ec_* DDL generation
assert mod.is_sqlite_only_table("_emdash_fts_posts_config") is True
assert mod.is_sqlite_only_table("ec_posts") is False
ec_ddl = mod.build_dynamic_ec_table_ddl(sys.argv[2], "ec_posts")
assert 'CREATE TABLE IF NOT EXISTS "ec_posts"' in ec_ddl, ec_ddl
assert '"id" TEXT PRIMARY KEY' in ec_ddl, ec_ddl
assert '"version" INTEGER DEFAULT 1' in ec_ddl, ec_ddl
assert "\"locale\" TEXT NOT NULL DEFAULT 'en'" in ec_ddl, ec_ddl

sqlite_info = mod.fetch_sqlite_tables(sys.argv[2])
pg_tables = {
    "users": {"id": ("integer", "int4"), "email": ("text", "text"), "is_admin": ("boolean", "bool"), "secret": ("text", "text")},
    "posts": {"id": ("integer", "int4"), "user_id": ("integer", "int4"), "meta": ("jsonb", "jsonb")},
}
sql, counts = mod.build_migration_sql(sys.argv[2], ["users", "posts"], sqlite_info, pg_tables, truncate_target=True)
assert counts == {"users": 1, "posts": 1}
assert "SET CONSTRAINTS ALL DEFERRED;" in sql
assert 'TRUNCATE TABLE "posts", "users" RESTART IDENTITY CASCADE;' in sql
assert sql.index('INSERT INTO "users"') < sql.index('INSERT INTO "posts"')
assert "TRUE" in sql
assert "'{\"views\":5}'::jsonb" in sql
assert "pg_get_serial_sequence" in sql
assert envelope in sql
PY

# 2b. Test CLI with mock psql (dry-run, happy path, and row-count mismatch rejection)
FAKE_BIN="${TMP_DIR}/fake-bin"
mkdir -p "${FAKE_BIN}"
cat >"${FAKE_BIN}/psql" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sql=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	-c | -tAc) shift; sql="$1" ;;
	esac
	shift || true
done
if [[ -z "${sql}" ]]; then
	body="$(cat)"
	if grep -Fq 'CREATE TABLE IF NOT EXISTS "ec_posts"' <<<"${body}" && [[ -n "${MOCK_PG_EC_CREATED_FLAG:-}" ]]; then
		touch "${MOCK_PG_EC_CREATED_FLAG}"
	fi
	exit 0
fi
if grep -Fq "information_schema.columns" <<<"${sql}"; then
	if [[ "${MOCK_PG_EMPTY_SCHEMA:-0}" == "1" ]]; then
		exit 0
	fi
	printf 'users\tid\tinteger\tint4\n'
	printf 'users\temail\ttext\ttext\n'
	printf 'users\tis_admin\tboolean\tbool\n'
	printf 'users\tsecret\ttext\ttext\n'
	printf 'posts\tid\tinteger\tint4\n'
	printf 'posts\tuser_id\tinteger\tint4\n'
	printf 'posts\tmeta\tjsonb\tjsonb\n'
	if [[ -f "${MOCK_PG_EC_CREATED_FLAG:-/nonexistent}" ]]; then
		printf 'ec_posts\tid\ttext\ttext\n'
		printf 'ec_posts\tslug\ttext\ttext\n'
		printf 'ec_posts\tstatus\ttext\ttext\n'
		printf 'ec_posts\tversion\tinteger\tint4\n'
		printf 'ec_posts\tlocale\ttext\ttext\n'
	fi
	exit 0
fi
if grep -Fq "information_schema.table_constraints" <<<"${sql}"; then
	printf 'posts\tusers\n'
	exit 0
fi
if grep -Fq "SELECT COUNT(*)" <<<"${sql}"; then
	printf '%s\n' "${MOCK_PG_COUNT:-0}"
	exit 0
fi
exit 0
EOF
chmod +x "${FAKE_BIN}/psql"

# Dry-run succeeds
DRY_OUT="$(PATH="${FAKE_BIN}:${PATH}" PGPASSWORD=x python3 "${SCRIPT_DIR}/lib/migrate-sqlite-to-pg.py" \
	--sqlite-path "${SQLITE_DB}" --pg-user u --pg-db d --dry-run)"
grep -Fq '"table": "users"' <<<"${DRY_OUT}"

# Empty check passes when MOCK_PG_COUNT=0 and fails when MOCK_PG_COUNT=5
PATH="${FAKE_BIN}:${PATH}" MOCK_PG_COUNT=0 PGPASSWORD=x python3 "${SCRIPT_DIR}/lib/migrate-sqlite-to-pg.py" \
	--sqlite-path "${SQLITE_DB}" --pg-user u --pg-db d --check-target-empty >/dev/null
if PATH="${FAKE_BIN}:${PATH}" MOCK_PG_COUNT=5 PGPASSWORD=x python3 "${SCRIPT_DIR}/lib/migrate-sqlite-to-pg.py" \
	--sqlite-path "${SQLITE_DB}" --pg-user u --pg-db d --check-target-empty >/dev/null 2>&1; then
	printf '[ERROR] --check-target-empty should fail on non-empty target\n' >&2
	exit 1
fi

# Row count mismatch MUST fail (MOCK_PG_COUNT=0 after insert of 1 row per table)
if PATH="${FAKE_BIN}:${PATH}" MOCK_PG_COUNT=0 PGPASSWORD=x python3 "${SCRIPT_DIR}/lib/migrate-sqlite-to-pg.py" \
	--sqlite-path "${SQLITE_DB}" --pg-user u --pg-db d --truncate-target >/dev/null 2>&1; then
	printf '[ERROR] migrator should fail on row count mismatch\n' >&2
	exit 1
fi

# Empty target PG schema MUST fail (refuse silent 0-table migration!)
if PATH="${FAKE_BIN}:${PATH}" MOCK_PG_EMPTY_SCHEMA=1 PGPASSWORD=x python3 "${SCRIPT_DIR}/lib/migrate-sqlite-to-pg.py" \
	--sqlite-path "${SQLITE_DB}" --pg-user u --pg-db d --truncate-target >/dev/null 2>&1; then
	printf '[ERROR] migrator must fail when target PG schema has 0 matching tables\n' >&2
	exit 1
fi

# Exact match succeeds (MOCK_PG_COUNT=1) including dynamic ec_posts creation and _emdash_fts_* skip
EC_FLAG="${TMP_DIR}/ec_created"
OK_OUT="$(PATH="${FAKE_BIN}:${PATH}" MOCK_PG_EC_CREATED_FLAG="${EC_FLAG}" MOCK_PG_COUNT=1 PGPASSWORD=x python3 "${SCRIPT_DIR}/lib/migrate-sqlite-to-pg.py" \
	--sqlite-path "${SQLITE_DB}" --pg-user u --pg-db d --truncate-target)"
[[ -f "${EC_FLAG}" ]]
grep -Fq '"status": "ok"' <<<"${OK_OUT}"
grep -Fq '"ec_posts": 1' <<<"${OK_OUT}"

# 3. Test scripts/migrate-runtime.sh (native-to-docker & docker-to-native --dry-run)
bash "${SCRIPT_DIR}/scripts/migrate-runtime.sh" --help >/dev/null

BAK_SRC="${TMP_DIR}/bak-src"
DOCKER_OUT="${TMP_DIR}/docker-out"
NATIVE_BAK="${TMP_DIR}/emdash-backup-20261124-120000.tar.gz"
mkdir -p "${BAK_SRC}/meta" "${BAK_SRC}/data/sqlite" "${BAK_SRC}/data/uploads" "${BAK_SRC}/site/.agents/skills" "${BAK_SRC}/site/.claude"
ln -s ../.agents/skills "${BAK_SRC}/site/.claude/skills"
cp "${SQLITE_DB}" "${BAK_SRC}/data/sqlite/data.db"
printf 'img-bytes' >"${BAK_SRC}/data/uploads/pic.bin"
cat >"${BAK_SRC}/meta/emdash.env" <<'EOF'
DB_DRIVER="sqlite"
SESSION_DRIVER="file"
STORAGE_DRIVER="local"
TEMPLATE="blog"
APP_PORT="3000"
APP_PUBLIC_URL="https://example.com"
EMDASH_ENCRYPTION_KEY="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
EOF
cat >"${BAK_SRC}/meta/manifest.json" <<'EOF'
{"schema_version":1,"db_driver":"sqlite","storage_driver":"local"}
EOF
tar -C "${BAK_SRC}" -czf "${NATIVE_BAK}" .

bash "${SCRIPT_DIR}/scripts/migrate-runtime.sh" native-to-docker \
	--backup "${NATIVE_BAK}" --out-dir "${DOCKER_OUT}" --yes >/dev/null

[[ -f "${DOCKER_OUT}/.env" ]]
[[ "$(stat -c '%a' "${DOCKER_OUT}/.env")" == "600" ]]
grep -Fq 'EMDASH_ENCRYPTION_KEY=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' "${DOCKER_OUT}/.env"

bash "${SCRIPT_DIR}/scripts/migrate-runtime.sh" docker-to-native \
	--backup "${NATIVE_BAK}" --docker-env "${DOCKER_OUT}/.env" --dry-run >/dev/null

printf '[INFO] migrate-db, fast-fail-google-fonts, and migrate-runtime regression checks passed\n'
