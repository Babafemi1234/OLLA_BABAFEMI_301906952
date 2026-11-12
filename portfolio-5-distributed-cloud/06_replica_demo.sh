#!/usr/bin/env bash
# 06_replica_demo.sh - one-script replication demo (primary 5432, replica 5433).
# Every line is real output; run_p5.sh saves it to replication_output.log.
set -euo pipefail
P="psql -h /var/run/postgresql -U freshfold -d freshfold -X -v ON_ERROR_STOP=1"
PRI="$P -p 5432"; REP="$P -p 5433"
EMAIL="repl.$(date +%s)@example.com"

echo "=== 1. Who is who ==="
echo "-- PRIMARY (port 5432):"; $PRI -c "SELECT current_setting('port') AS port, pg_is_in_recovery() AS is_replica;"
echo "-- REPLICA (port 5433):"; $REP -c "SELECT current_setting('port') AS port, pg_is_in_recovery() AS is_replica;"

echo; echo "=== 2. A write on the REPLICA must be rejected (read-only standby) ==="
if $REP -c "INSERT INTO customer (full_name, phone, email, area_id, address) VALUES ('Replica Write Test','0809 111 0000','$EMAIL',1,'1 Test Rd, Lekki');" 2>&1; then
  echo "UNEXPECTED: replica accepted a write"; exit 1
else echo "-> rejected as expected (replica is read-only)"; fi

echo; echo "=== 3. Insert on the PRIMARY ==="
$PRI -c "INSERT INTO customer (full_name, phone, email, area_id, address) VALUES ('Replica Stream Test','0809 111 0001','$EMAIL',1,'2 Test Rd, Lekki') RETURNING customer_id, email;"
sleep 1

echo; echo "=== 4. The row arrives on the REPLICA (streamed WAL) ==="
$REP -c "SELECT customer_id, full_name, email FROM customer WHERE email='$EMAIL';"

echo; echo "=== 5. Replication status (PRIMARY view) ==="
$PRI -c "SELECT application_name, state, sync_state, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes FROM pg_stat_replication;"

echo; echo "=== 6. Replica replay delay (REPLICA view) ==="
$REP -c "SELECT pg_last_wal_replay_lsn() AS replayed_lsn, now() - pg_last_xact_replay_timestamp() AS delay;"
echo; echo "Replication demo complete."
