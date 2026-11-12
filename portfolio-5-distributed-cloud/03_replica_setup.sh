#!/usr/bin/env bash
# =============================================================================
# 03_replica_setup.sh  —  Portfolio 5 streaming physical replica setup
# Portfolio 5 · MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111
#
# Sets up a SECOND PostgreSQL 16 instance (a streaming physical replica) on
# port 5433, in the same Codespace, alongside the primary on port 5432.
#
# Codespaces rules honoured (see repo README):
#   * sudo only as root -> `sudo runuser -u postgres -- ...`, never sudo -u postgres
#   * PostgreSQL config lives in /etc/postgresql/16/main/ ; the pg_ctl binary is
#     /usr/lib/postgresql/16/bin/pg_ctl
#   * pg_hba.conf trust lines go at the TOP of the file (first match wins)
#   * TCP logins need a password, so replication + client connections go through
#     the Unix socket (host=/var/run/postgresql)
#   * No postgres_fdw used anywhere
#
# Run this script with sudo:
#     sudo bash 03_replica_setup.sh
#
# It is idempotent: re-running it refreshes the replica from the primary.
# =============================================================================

set -euo pipefail

PRIMARY_PORT=5432
REPLICA_PORT=5433
REPLICA_DIR="/var/lib/postgresql/16/replica"
REPLICA_LOG="/var/log/postgresql/replica.log"
PG_CTL="/usr/lib/postgresql/16/bin/pg_ctl"
HBA="/etc/postgresql/16/main/pg_hba.conf"
PGCONF="/etc/postgresql/16/main/postgresql.conf"

echo "============================================================"
echo " Portfolio 5 — streaming replica setup (primary 5432, replica 5433)"
echo "============================================================"

# ---------------------------------------------------------------------------
# 1. Primary: replication settings via ALTER SYSTEM (writes postgresql.auto.conf)
# ---------------------------------------------------------------------------
echo "[1/7] configuring primary for replication ..."
sudo runuser -u postgres -- psql -p $PRIMARY_PORT -v ON_ERROR_STOP=1 <<'SQL'
ALTER SYSTEM SET wal_level            = replica;
ALTER SYSTEM SET max_wal_senders      = 10;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET hot_standby          = on;   -- used by the replica
SELECT pg_reload_conf();
SQL

# ---------------------------------------------------------------------------
# 2. Primary pg_hba.conf: prepend a replication + local trust line at the TOP.
#    First-match-wins means a later scram line must NOT shadow our trust line.
#    We use a marker so re-running does not duplicate the block.
# ---------------------------------------------------------------------------
echo "[2/7] prepending replication trust lines to the TOP of pg_hba.conf ..."
if ! sudo grep -q "BEGIN freshfold-replica-trust" "$HBA"; then
    sudo cp "$HBA" "${HBA}.bak.$(date +%s)"
    sudo tee "$HBA.tmp" >/dev/null <<'EOF'
# BEGIN freshfold-replica-trust (Portfolio 5) — must stay at the top
#   allow the local replicator role to connect over the Unix socket (no TCP,
#   no password) and allow all local connections as trust (Codespaces).
local   replication  replicator                              trust
local   all          all                                     trust
host    replication  replicator  127.0.0.1/32                trust
host    replication  replicator  ::1/128                     trust
host    all          all         127.0.0.1/32                 trust
# END freshfold-replica-trust
EOF
    sudo cat "$HBA" | sudo tee -a "$HBA.tmp" >/dev/null
    sudo mv "$HBA.tmp" "$HBA"
    sudo chown postgres:postgres "$HBA"
    sudo chmod 640 "$HBA"
    echo "  prepended trust block to $HBA"
else
    echo "  trust block already present, skipping"
fi

# ---------------------------------------------------------------------------
# 3. Restart the primary so wal_level / pg_hba take effect.
# ---------------------------------------------------------------------------
echo "[3/7] restarting the primary ..."
sudo pg_ctlcluster 16 main restart

# ---------------------------------------------------------------------------
# 4. Create the replication role (idempotent).
# ---------------------------------------------------------------------------
echo "[4/7] creating replication role 'replicator' ..."
sudo runuser -u postgres -- psql -p $PRIMARY_PORT -tAc \
  "SELECT 1 FROM pg_roles WHERE rolname='replicator'" | grep -q 1 \
  || sudo runuser -u postgres -- psql -p $PRIMARY_PORT -c \
       "CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replpass';"

# ---------------------------------------------------------------------------
# 5. Stop the old replica if running, then take a fresh base backup.
#    pg_basebackup is run as the postgres OS user, over the Unix socket (no
#    TCP, no password thanks to the trust line above). -R writes standby.signal
#    + primary_conninfo (pointing at the Unix socket) into the replica's
#    postgresql.auto.conf.
# ---------------------------------------------------------------------------
echo "[5/7] taking a fresh base backup of the primary into $REPLICA_DIR ..."
if [ -d "$REPLICA_DIR" ] && sudo runuser -u postgres -- "$PG_CTL" -D "$REPLICA_DIR" -m fast stop 2>/dev/null; then
    echo "  stopped an existing replica"
fi
sudo rm -rf "$REPLICA_DIR"
sudo mkdir -p "$REPLICA_DIR"
sudo chown postgres:postgres "$REPLICA_DIR"
sudo chmod 700 "$REPLICA_DIR"
# pg_basebackup needs an EMPTY target directory; it copies the primary's data
# files + configs and (with -R) writes standby.signal + primary_conninfo.
sudo runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_basebackup \
    -h /var/run/postgresql -p $PRIMARY_PORT -U replicator \
    -D "$REPLICA_DIR" -Fp -Xs -P -R

# ---------------------------------------------------------------------------
# 6. The replica needs its OWN postgresql.conf, because Debian keeps the
#    config in /etc/postgresql/16/main/ (NOT in the data dir), and pg_basebackup
#    copies only the data dir. If we started the replica with the primary's
#    postgresql.conf it would (a) point data_directory at the PRIMARY's data
#    dir and (b) bind port 5432 — both fatal. So we copy the primary's config
#    into the replica data dir and sed three lines:
#      data_directory     -> /var/lib/postgresql/16/replica  (this data dir)
#      external_pid_file  -> a replica-specific pid file
#      port               -> 5433
#    hba_file / ident_file are left pointing at /etc/postgresql/16/main/ which
#    already has the trust block at the top (we added it in step 2), so local
#    connections to the replica work without a password.
#    pg_basebackup -R already wrote standby.signal + primary_conninfo into the
#    replica's postgresql.auto.conf (pointing at the Unix socket).
# ---------------------------------------------------------------------------
echo "[6/7] copying + adjusting the replica's postgresql.conf ..."
sudo cp /etc/postgresql/16/main/postgresql.conf "$REPLICA_DIR/postgresql.conf"
sudo cp /etc/postgresql/16/main/pg_ident.conf   "$REPLICA_DIR/pg_ident.conf"
sudo chown postgres:postgres "$REPLICA_DIR/postgresql.conf" "$REPLICA_DIR/pg_ident.conf"

# Re-point data_directory at THIS data dir (Debian's default points at the
# primary's data dir, which would corrupt the primary).
sudo sed -i -E "s|^[[:space:]]*data_directory[[:space:]]*=.*|data_directory = '$REPLICA_DIR'|" "$REPLICA_DIR/postgresql.conf"
# Give the replica its own pid file (the primary's pid file would conflict).
sudo sed -i -E "s|^[[:space:]]*external_pid_file[[:space:]]*=.*|external_pid_file = '/var/run/postgresql/16-replica.pid'|" "$REPLICA_DIR/postgresql.conf"
# Port: delete any existing (commented or not) port = line, then append our own.
sudo sed -i -E '/^[[:space:]]*#?[[:space:]]*port[[:space:]]*=/d' "$REPLICA_DIR/postgresql.conf"
sudo sed -i -E "s|^[[:space:]]*include_dir.*|#&|" "$REPLICA_DIR/postgresql.conf"   # conf.d does not exist in the replica dir
sudo sed -i -E "s|^[[:space:]]*cluster_name[[:space:]]*=.*|cluster_name = 'replica'|" "$REPLICA_DIR/postgresql.conf"
echo "port = 5433" | sudo tee -a "$REPLICA_DIR/postgresql.conf" >/dev/null
# hot_standby is on by default in PostgreSQL 10+, but set it explicitly.
echo "hot_standby = on" | sudo tee -a "$REPLICA_DIR/postgresql.auto.conf" >/dev/null
sudo chown postgres:postgres "$REPLICA_DIR/postgresql.auto.conf"

# ---------------------------------------------------------------------------
# 7. Start the replica with pg_ctl (NOT pg_ctlcluster, which manages only the
#    one main instance). The copied postgresql.conf already sets
#    unix_socket_directories = '/var/run/postgresql', so the replica creates
#    /var/run/postgresql/.s.PGSQL.5433 and we can connect over the socket.
# ---------------------------------------------------------------------------
echo "[7/7] starting the replica ..."
sudo runuser -u postgres -- "$PG_CTL" -D "$REPLICA_DIR" \
    -l "$REPLICA_LOG" -w start

echo "============================================================"
echo " Replica setup complete."
echo "   PRIMARY  : port 5432  (socket /var/run/postgresql)"
echo "   REPLICA  : port 5433  (socket /var/run/postgresql)"
echo "============================================================"
echo "Verify (run as the postgres OS user):"
echo "  sudo runuser -u postgres -- psql -p 5432 -c 'SELECT application_name, state, sync_state FROM pg_stat_replication;'"
echo "  sudo runuser -u postgres -- psql -p 5433 -c 'SELECT pg_is_in_recovery();'"
echo "Then follow 04_replica_test_guide.md to show the replica rejecting"
echo "writes and streaming new rows from the primary."
