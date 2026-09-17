#!/usr/bin/env bash
# Restore-Proof destructive test — run this ON Bastion (over SSH).
# Isolated project name/volumes so it never touches the real cloudLab stack.
set -euo pipefail

PROJECT="restoreproof"
CONTAINER="restoreproof_pg"
VOLUME="restoreproof_pgdata"
DUMPFILE="/root/restoreproof_backup.sql"
LOG() { echo "[$(date '+%H:%M:%S')] $*"; }

LOG "=== Restore-Proof destructive test starting ==="

LOG "Step 1: clean slate — remove any leftover demo container/volume from a prior run"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker volume rm "$VOLUME" >/dev/null 2>&1 || true

LOG "Step 2: start a disposable Postgres (isolated volume, not the real stack)"
docker run -d --name "$CONTAINER" \
  -e POSTGRES_PASSWORD=demo \
  -v "$VOLUME":/var/lib/postgresql/data \
  postgres:16 >/dev/null
sleep 5

LOG "Step 3: seed fake data (100 rows) — this simulates real customer data"
docker exec -i "$CONTAINER" psql -U postgres -c \
  "CREATE TABLE customers (id serial PRIMARY KEY, email text, created_at timestamp default now());" >/dev/null
docker exec -i "$CONTAINER" psql -U postgres -c \
  "INSERT INTO customers (email) SELECT 'user' || g || '@example.com' FROM generate_series(1,100) g;" >/dev/null

BEFORE_COUNT=$(docker exec -i "$CONTAINER" psql -U postgres -tAc "SELECT count(*) FROM customers;")
BEFORE_CHECKSUM=$(docker exec -i "$CONTAINER" psql -U postgres -tAc "SELECT md5(string_agg(email, ',' ORDER BY id)) FROM customers;")
LOG "Before: $BEFORE_COUNT rows, checksum $BEFORE_CHECKSUM"

LOG "Step 4: take the backup (this is the thing everyone assumes works)"
docker exec -i "$CONTAINER" pg_dump -U postgres postgres > "$DUMPFILE"
LOG "Backup written to $DUMPFILE ($(wc -c < "$DUMPFILE") bytes)"

LOG "=== Step 5: DESTROY IT — killing the container and deleting the volume, on purpose ==="
DESTROY_TIME=$(date +%s)
docker rm -f "$CONTAINER" >/dev/null
docker volume rm "$VOLUME" >/dev/null
LOG "Container + volume are gone. This is the pgdata-wiped-with-no-backup scenario — except we have the backup."

LOG "Step 6: bring up a fresh, empty Postgres (proves the old data is truly gone)"
docker run -d --name "$CONTAINER" \
  -e POSTGRES_PASSWORD=demo \
  -v "$VOLUME":/var/lib/postgresql/data \
  postgres:16 >/dev/null
sleep 5
EMPTY_CHECK=$(docker exec -i "$CONTAINER" psql -U postgres -tAc "SELECT to_regclass('customers');" || echo "")
LOG "Fresh DB check (should be empty/no table): '$EMPTY_CHECK'"

LOG "Step 7: RESTORE from the backup"
cat "$DUMPFILE" | docker exec -i "$CONTAINER" psql -U postgres postgres >/dev/null
RESTORE_DONE_TIME=$(date +%s)

AFTER_COUNT=$(docker exec -i "$CONTAINER" psql -U postgres -tAc "SELECT count(*) FROM customers;")
AFTER_CHECKSUM=$(docker exec -i "$CONTAINER" psql -U postgres -tAc "SELECT md5(string_agg(email, ',' ORDER BY id)) FROM customers;")
LOG "After restore: $AFTER_COUNT rows, checksum $AFTER_CHECKSUM"

ELAPSED=$((RESTORE_DONE_TIME - DESTROY_TIME))
LOG "=== Time from destruction to verified restore: ${ELAPSED}s ==="

if [ "$BEFORE_COUNT" = "$AFTER_COUNT" ] && [ "$BEFORE_CHECKSUM" = "$AFTER_CHECKSUM" ]; then
  LOG "RESULT: PASS — data matches exactly (row count + checksum identical)."
else
  LOG "RESULT: FAIL — mismatch. before=$BEFORE_COUNT/$BEFORE_CHECKSUM after=$AFTER_COUNT/$AFTER_CHECKSUM"
fi

LOG "Step 8: cleanup — tearing down the demo container/volume, leaving Bastion clean"
docker rm -f "$CONTAINER" >/dev/null
docker volume rm "$VOLUME" >/dev/null
rm -f "$DUMPFILE"

LOG "=== Restore-Proof destructive test complete ==="
