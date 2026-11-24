#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

MOCK_S3_DIR="${TMP_DIR}/mock-s3"
MOCK_PY="${TMP_DIR}/mock-py"
ROOT_DIR="${TMP_DIR}/data-emdash"
ENV_FILE="${TMP_DIR}/emdash.env"
FAKE_BIN="${TMP_DIR}/fake-bin"

mkdir -p "${MOCK_S3_DIR}/test-bucket/site-a" "${MOCK_PY}/botocore" "${ROOT_DIR}/data/sqlite" "${ROOT_DIR}/data/uploads" "${ROOT_DIR}/backups" "${ROOT_DIR}/app/site" "${FAKE_BIN}"

# Minimal mock botocore.config + boto3 backed by local filesystem
: >"${MOCK_PY}/botocore/__init__.py"
cat >"${MOCK_PY}/botocore/config.py" <<'PY'
class Config:
    def __init__(self, **kwargs):
        self.kwargs = kwargs
PY

cat >"${MOCK_PY}/boto3.py" <<'PY'
import datetime, os, shutil
from pathlib import Path

ROOT = Path(os.environ["MOCK_S3_DIR"])

class _Paginator:
    def __init__(self, client):
        self._client = client

    def paginate(self, Bucket, Prefix=""):
        yield self._client.list_objects_v2(Bucket=Bucket, Prefix=Prefix)

class _Client:
    def upload_file(self, filename, bucket, key):
        dst = ROOT / bucket / key
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(filename, dst)

    def upload_fileobj(self, fileobj, bucket, key):
        dst = ROOT / bucket / key
        dst.parent.mkdir(parents=True, exist_ok=True)
        with open(dst, "wb") as out:
            shutil.copyfileobj(fileobj, out)

    def download_file(self, bucket, key, filename):
        src = ROOT / bucket / key
        if not src.is_file():
            raise FileNotFoundError(f"S3 object not found: {bucket}/{key}")
        shutil.copy2(src, filename)

    def download_fileobj(self, bucket, key, fileobj):
        src = ROOT / bucket / key
        if not src.is_file():
            raise FileNotFoundError(f"S3 object not found: {bucket}/{key}")
        with open(src, "rb") as fh:
            shutil.copyfileobj(fh, fileobj)

    def get_paginator(self, op_name):
        assert op_name == "list_objects_v2"
        return _Paginator(self)

    def list_objects_v2(self, Bucket, Prefix="", ContinuationToken=None):
        base = ROOT / Bucket
        contents = []
        if base.is_dir():
            for p in sorted(base.rglob("*")):
                if not p.is_file():
                    continue
                rel = p.relative_to(base).as_posix()
                if Prefix and not rel.startswith(Prefix):
                    continue
                st = p.stat()
                contents.append({
                    "Key": rel,
                    "Size": st.st_size,
                    "LastModified": datetime.datetime.fromtimestamp(st.st_mtime, tz=datetime.timezone.utc),
                })
        return {"Contents": contents, "IsTruncated": False}

    def delete_object(self, Bucket, Key):
        p = ROOT / Bucket / Key
        if p.exists():
            p.unlink()
        return {"Deleted": True}

    def delete_objects(self, Bucket, Delete):
        for obj in Delete.get("Objects", []):
            p = ROOT / Bucket / obj["Key"]
            if p.exists():
                p.unlink()
        return {"Deleted": Delete.get("Objects", [])}

def client(service, **kwargs):
    assert service == "s3"
    return _Client()
PY

# Mock systemctl, chown, and curl so restore can complete offline
cat >"${FAKE_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"${FAKE_BIN}/chown" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"${FAKE_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
printf '{"data":{"needsSetup":false}}\n'
exit 0
EOF
chmod +x "${FAKE_BIN}/systemctl" "${FAKE_BIN}/chown" "${FAKE_BIN}/curl"

# Create initial SQLite DB + upload file
python3 - "${ROOT_DIR}/data/sqlite/data.db" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT)")
conn.execute("INSERT INTO posts (id, title) VALUES (1, 'hello-s3-roundtrip')")
conn.commit()
conn.close()
PY
printf 'upload-payload\n' >"${ROOT_DIR}/data/uploads/file1.txt"

cat >"${ENV_FILE}" <<EOF
ROOT_DIR="${ROOT_DIR}"
CONFIG_DIR="${TMP_DIR}"
APP_ENV_FILE="${ENV_FILE}"
INSTALL_YAML="${TMP_DIR}/install.yml"
SITE_DIR="${ROOT_DIR}/app/site"
SQLITE_PATH="${ROOT_DIR}/data/sqlite/data.db"
UPLOADS_DIR="${ROOT_DIR}/data/uploads"
BACKUP_DIR="${ROOT_DIR}/backups"
DB_DRIVER="sqlite"
SESSION_DRIVER="file"
STORAGE_DRIVER="local"
APP_BIND_HOST="127.0.0.1"
APP_PORT="3000"
APP_PUBLIC_URL="http://127.0.0.1:3000"
APP_RUN_USER="$(id -un)"
APP_RUN_GROUP="$(id -gn)"
APP_SYSTEMD_SERVICE="emdash-app"
BACKUP_KEEP_LOCAL="5"
BACKUP_KEEP_S3="2"
BACKUP_TARGET_TYPE="s3"
BACKUP_ENCRYPTION_PASSPHRASE="s3-test-passphrase-123"
BACKUP_S3_ENDPOINT="https://mock-s3.local"
BACKUP_S3_REGION="auto"
BACKUP_S3_BUCKET="test-bucket"
BACKUP_S3_ACCESS_KEY_ID="AKIA_TEST"
BACKUP_S3_SECRET_ACCESS_KEY="SECRET_TEST"
BACKUP_S3_PREFIX="site-a"
EOF

# Seed 3 older matching backups + 1 non-matching user object in the same prefix
printf 'old1' >"${MOCK_S3_DIR}/test-bucket/site-a/emdash-backup-20250101-010000.tar.gz.enc"
printf 'old2' >"${MOCK_S3_DIR}/test-bucket/site-a/emdash-backup-20250102-010000.tar.gz.enc"
printf 'old3' >"${MOCK_S3_DIR}/test-bucket/site-a/emdash-backup-20250103-010000.tar.gz.enc"
touch -t 202501010100 "${MOCK_S3_DIR}/test-bucket/site-a/emdash-backup-20250101-010000.tar.gz.enc"
touch -t 202501020100 "${MOCK_S3_DIR}/test-bucket/site-a/emdash-backup-20250102-010000.tar.gz.enc"
touch -t 202501030100 "${MOCK_S3_DIR}/test-bucket/site-a/emdash-backup-20250103-010000.tar.gz.enc"
printf 'do-not-delete' >"${MOCK_S3_DIR}/test-bucket/site-a/keep-me-forever.txt"

export MOCK_S3_DIR
export PYTHONPATH="${MOCK_PY}:${PYTHONPATH:-}"
export EMDASH_INSTALL_ENV_FILE="${ENV_FILE}"
export EMDASH_LOCK_FILE="${TMP_DIR}/s3.lock"
export PATH="${FAKE_BIN}:${PATH}"

# 1. Run encrypted backup -> uploads to S3 and prunes remote to BACKUP_KEEP_S3=2
bash "${SCRIPT_DIR}/emdashctl" backup --encrypt >/dev/null

# Verify non-matching object was NEVER deleted
[[ -f "${MOCK_S3_DIR}/test-bucket/site-a/keep-me-forever.txt" ]]

# 2. List S3 backups in JSON and verify exactly 2 managed backups remain, sorted newest-first
LIST_JSON="$(bash "${SCRIPT_DIR}/emdashctl" backup --list-s3 --json)"
python3 - "${LIST_JSON}" <<'PY'
import json, sys
objs = json.loads(sys.argv[1])
assert isinstance(objs, list), f"expected list, got {type(objs)}"
assert len(objs) == 2, f"expected 2 retained S3 backups, got {len(objs)}: {objs}"
assert objs[0]["key"] > objs[1]["key"], "expected newest-first ordering"
assert objs[1]["key"].endswith("emdash-backup-20250103-010000.tar.gz.enc"), f"unexpected second key: {objs[1]}"
PY

# 3. Corrupt local SQLite DB & delete upload, then restore via --from-s3 latest
python3 - "${ROOT_DIR}/data/sqlite/data.db" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("UPDATE posts SET title = 'corrupted-local' WHERE id = 1")
conn.commit()
conn.close()
PY
rm -f "${ROOT_DIR}/data/uploads/file1.txt"

(
	# shellcheck source=../emdashctl
	source "${SCRIPT_DIR}/emdashctl"
	systemctl() { return 0; }
	wait_http_ok() { return 0; }
	main restore --from-s3 latest --yes >/dev/null
)

RESTORED_TITLE="$(python3 -c "import sqlite3; print(sqlite3.connect('${ROOT_DIR}/data/sqlite/data.db').execute('SELECT title FROM posts WHERE id=1').fetchone()[0])")"
[[ "${RESTORED_TITLE}" == "hello-s3-roundtrip" ]]
[[ -f "${ROOT_DIR}/data/uploads/file1.txt" ]]

printf '[INFO] S3 backup retention, list-s3, and restore --from-s3 regression checks passed\n'
