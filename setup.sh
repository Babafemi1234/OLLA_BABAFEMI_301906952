#!/usr/bin/env bash
# =============================================================================
# setup.sh — FreshFold Laundry portfolio environment setup
# Course : MIT 8103 Advanced Database Systems (Miva Open University)
# Student: Olla Babafemi  |  2026/A/MIT/0111
# Target : GitHub Codespaces (Ubuntu 24.04 default image)
#
# What this script does
#   1. Removes the stale yarn apt source that breaks apt-get update in Codespaces.
#   2. Installs PostgreSQL 16 and MongoDB 8 (community server).
#   3. Starts both services.
#   4. Creates the PostgreSQL role + database used by every portfolio.
#   5. Creates the MongoDB database + read user used by Portfolio 4.
#   6. Installs the Python dependencies used by the bulk generators.
#
# Codespaces rules honoured by this script (see repo README "Codespaces rules"):
#   * The codespace user can sudo only as root, so we use:
#         sudo runuser -u postgres -- <command>
#     never  `sudo -u postgres <command>`.
#   * PostgreSQL config lives in /etc/postgresql/16/main/ ; the pg_ctl binary is
#     /usr/lib/postgresql/16/bin/pg_ctl.
#   * TCP logins require a password, so all psql calls in this repo go through
#     the Unix socket (host=/var/run/postgresql) — see each run_pN.sh.
#   * We do NOT use postgres_fdw anywhere in the portfolio.
#   * The stale yarn list is removed before apt-get update.
#   * All dates in the seeded/generated data are relative to today (CURRENT_DATE),
#     so the data never "expires" when the portfolio is re-run in the future.
# =============================================================================

set -euo pipefail

echo "============================================================"
echo " FreshFold Laundry — portfolio environment setup (Codespaces)"
echo "============================================================"

# 0. Remove stale yarn apt source that breaks apt-get update in Codespaces
YARN_LIST="/etc/apt/sources.list.d/yarn.list"
if [ -f "$YARN_LIST" ]; then
  echo "[0] Removing stale $YARN_LIST (Codespaces fix) ..."
  sudo rm -f "$YARN_LIST"
fi

echo "[1] apt-get update ..."
sudo apt-get update -y || true

# ---------------------------------------------------------------------------
# 1. PostgreSQL 16 — add the official PostgreSQL apt repo so PG16 installs on
#    any Ubuntu version Codespaces happens to use (22.04 ships PG14 by default;
#    24.04 ships PG16). The PGDG repo gives us postgresql-16 explicitly.
# ---------------------------------------------------------------------------
echo "[1.5] Adding the PostgreSQL apt repository (PGDG) ..."
sudo apt-get install -y curl ca-certificates gnupg lsb-release
sudo install -d /usr/share/postgresql-common/pgdg
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  | gpg --dearmor | sudo tee /usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg >/dev/null
. /etc/os-release
sudo tee /etc/apt/sources.list.d/pgdg.list >/dev/null <<EOF
deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main
EOF
sudo apt-get update -y || true

echo "[2] Installing PostgreSQL 16 ..."
sudo apt-get install -y postgresql-16 postgresql-contrib-16 postgresql-client-16 \
     libpq-dev python3-psycopg2

# Extensions needed by the portfolio (btree_gist for rider exclusion
# constraint, pg_trgm optional for name search).
echo "[3] Enabling PostgreSQL contrib extensions ..."
sudo runuser -u postgres -- psql -d postgres -c "CREATE EXTENSION IF NOT EXISTS btree_gist;" 2>/dev/null || true
sudo runuser -u postgres -- psql -d postgres -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"     2>/dev/null || true

echo "[4] Starting PostgreSQL 16 ..."
sudo pg_ctlcluster 16 main start 2>/dev/null || true
# Confirm it is up; the cluster is normally auto-started by the installer.
sudo pg_ctlcluster 16 main status || sudo service postgresql start

# Create the application role + database. We connect through the Unix socket
# as the postgres OS user (no TCP, no password needed on the socket).
echo "[5] Creating PostgreSQL role 'freshfold' and database 'freshfold' ..."
if ! sudo runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='freshfold'" | grep -q 1; then
  sudo runuser -u postgres -- psql -d postgres -c "CREATE ROLE freshfold WITH LOGIN SUPERUSER;"
fi
sudo runuser -u postgres -- psql -d postgres -c "CREATE DATABASE freshfold OWNER freshfold;" 2>/dev/null || true
# btree_gist must exist in the freshfold database too.
sudo runuser -u postgres -- psql -d freshfold -c "CREATE EXTENSION IF NOT EXISTS btree_gist;"
sudo runuser -u postgres -- psql -d freshfold -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"

# Peer authentication would reject role 'freshfold' for the OS user 'codespace'.
# Allow the freshfold role on the local Unix socket (top of pg_hba.conf, once).
HBA=/etc/postgresql/16/main/pg_hba.conf
if ! sudo grep -q "freshfold-trust" "$HBA"; then
  sudo sed -i '1i local all freshfold trust # freshfold-trust' "$HBA"
  sudo pg_ctlcluster 16 main reload
fi
sudo runuser -u postgres -- psql -d postgres -c "ALTER DATABASE freshfold SET timezone TO 'Africa/Lagos';"

echo "    PostgreSQL ready.  Connect with:"
echo "      PGPASSWORD= psql -h /var/run/postgresql -U freshfold -d freshfold"
echo "    (Unix-socket connection — no TCP, no password needed locally)"

# ---------------------------------------------------------------------------
# 2. MongoDB 8
# ---------------------------------------------------------------------------
echo "[6] Installing MongoDB 8 (community server) ..."
# Import the official MongoDB 8.0 GPG key and list file for Ubuntu 22.04/24.04.
wget -qO- https://www.mongodb.org/static/pgp/server-8.0.asc | \
  gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/mongodb-server-8.0.gpg >/dev/null

# Detect the Ubuntu codename; mongodb packages publish jammy/noble. Fall back
# to jammy if the codename is not in the MongoDB repo yet.
. /etc/os-release
MONGO_DISTRO="${VERSION_CODENAME:-jammy}"
case "$MONGO_DISTRO" in
  noble) MONGO_DISTRO="noble" ;;
  *)     MONGO_DISTRO="jammy" ;;   # safe fallback supported by MongoDB 8.0
esac

echo "deb [ arch=amd64,arm64 signed-by=/etc/apt/trusted.gpg.d/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${MONGO_DISTRO}/mongodb-org/8.0 multiverse" \
  | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list >/dev/null

sudo apt-get update -y || true
sudo apt-get install -y mongodb-org

echo "[7] Starting MongoDB 8 ..."
# Codespaces does not use systemd the same way; start mongod directly.
sudo mkdir -p /data/db /var/log/mongodb
sudo chown -R "$(id -u):$(id -g)" /data/db /var/log/mongodb 2>/dev/null || sudo chown -R mongodb:mongodb /data/db /var/log/mongodb
if ! pgrep -x mongod >/dev/null 2>&1; then
  sudo mongod --fork --logpath /var/log/mongodb/mongod.log \
       --dbpath /data/db --bind_ip 127.0.0.1 --port 27017
fi
sleep 3
pgrep -x mongod >/dev/null && echo "    MongoDB is running on 127.0.0.1:27017" || echo "    [WARN] mongod not detected — check /var/log/mongodb/mongod.log"

echo "[8] Creating MongoDB user for the 'freshfold' database ..."
mongosh --quiet --eval '
const conn = db.getSiblingDB("admin");
try {
  conn.createUser({
    user: "freshfold",
    pwd: "freshfold",
    roles: [{ role: "readWrite", db: "freshfold" }, { role: "readWrite", db: "admin" }]
  });
} catch (e) { print("freshfold user already exists or Mongo requires auth off — continuing."); }
'
echo "    Mongo connect string: mongodb://freshfold:freshfold@127.0.0.1:27017/freshfold"
echo "    (or unauthenticated: mongodb://127.0.0.1:27017/freshfold if auth is off)"

# ---------------------------------------------------------------------------
# 3. Python deps used by the bulk generators (P1 50k orders, P4 40k garments)
# ---------------------------------------------------------------------------
echo "[9] Installing Python dependencies (with fallbacks) ..."
sudo apt-get install -y python3-pip python3-venv || true
PKGS="pymongo psycopg2-binary Faker"
if ! python3 -c 'import psycopg2, pymongo, faker' 2>/dev/null; then
  python3 -m pip install --quiet $PKGS \
   || python3 -m pip install --quiet --user $PKGS \
   || python3 -m pip install --quiet --break-system-packages $PKGS \
   || python3 -m pip install --quiet --user --break-system-packages $PKGS \
   || sudo apt-get install -y python3-psycopg2 python3-pymongo python3-faker || true
fi
python3 -c 'import psycopg2, pymongo, faker; print("    Python libraries OK: psycopg2, pymongo, faker")'

echo "[10] Installing mongosh (if not present) ..."
sudo apt-get install -y mongodb-mongosh 2>/dev/null || true

echo "============================================================"
echo " Setup complete."
echo " PostgreSQL 16  ->  socket /var/run/postgresql, db 'freshfold'"
echo " MongoDB 8      ->  127.0.0.1:27017, db 'freshfold'"
echo "============================================================"
echo "Next step:"
echo "  cd advanced-database-portfolio"
echo "  ./portfolio-1-database-design/run_p1.sh   # build schema + seed + bulk data"
echo "  ./portfolio-2-query-optimisation/run_p2.sh # queries + EXPLAIN ANALYZE"
echo "  ./portfolio-3-transactions-concurrency/run_p3.sh"
echo "  ./portfolio-4-nosql/run_p4.sh"
echo "  ./portfolio-5-distributed-cloud/run_p5.sh"
