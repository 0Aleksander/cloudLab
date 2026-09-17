# Restore-Proof: a destructive backup test, on the record

Most backups are hope, not protection — nobody finds out whether theirs actually restores until the day they need it. This is a real, isolated destructive test run against production infrastructure ([Bastion](../README.md)), not a demo environment: a database gets seeded with data, backed up, **deliberately destroyed**, then restored from nothing but the backup — with the before/after checksummed to prove the data is byte-for-byte identical, not just "a table with the same name."

## What was tested

1. Started a disposable PostgreSQL container with its own isolated volume (never touches Bastion's real services)
2. Seeded 100 rows of fake customer data
3. Took a `pg_dump` backup — the thing every setup *assumes* works
4. **Killed the container and deleted its volume** — the exact "pgdata directory got wiped, no backup behind it" failure mode that takes down real SaaS products
5. Brought up a completely fresh, empty Postgres to prove the old data was actually gone, not just hidden
6. Restored from the backup
7. Verified the restored data against the original by row count **and** an MD5 checksum of the actual contents

## Result

```
Before:  100 rows, checksum 925cd243a9cb8cf72883f376e2ce4c07
After:   100 rows, checksum 925cd243a9cb8cf72883f376e2ce4c07
Time from destruction to verified restore: 7 seconds
RESULT: PASS
```

Full raw terminal output: [`transcript.txt`](./transcript.txt). Script: [`run-test.sh`](./run-test.sh).

## Why this, not just "we set up backups"

Anyone can ask an AI assistant to write a backup script in five minutes. Almost nobody actually destroys something on purpose to prove the restore works — because it's the step people are afraid to run against their own data. This repo is that step, done in the open, with the receipts.
