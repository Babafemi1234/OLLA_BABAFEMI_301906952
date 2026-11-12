#!/usr/bin/env bash
# =============================================================================
# run_p5.sh  —  Portfolio 5 (Distributed and Cloud Database Exercise) runner
# MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111
#
# Runs the SINGLE-SESSION, automation-safe parts of Portfolio 5:
#   1. 01_partitioning.sql  — partition the orders by month, migrate data,
#        demonstrate partition pruning with EXPLAIN.
#
# The streaming replica setup (03_replica_setup.sh) needs sudo and modifies
# system PostgreSQL config, so it is run separately (this script prints the
# exact command). The replica test (04_replica_test_guide.md) needs two
# interactive psql sessions.
#
# All psql calls go through the Unix socket (host=/var/run/postgresql) so no
# password is needed in Codespaces. See README "Codespaces rules".
# =============================================================================

set -euo pipefail

PSQL="psql -h /var/run/postgresql -U freshfold -d freshfold -v ON_ERROR_STOP=1"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "============================================================"
echo " Portfolio 5 — Distributed and Cloud Database Exercise"
echo "============================================================"

echo "[1/3] Partitioning the orders table by month ..."
$PSQL -f "$HERE/01_partitioning.sql"

echo "[2/3] Setting up the streaming read replica (primary 5432, replica 5433) ..."
bash "$HERE/03_replica_setup.sh" 2>&1 | tee "$HERE/replica_setup_output.log"

echo "[3/3] Replication demo (write rejected on replica, row streams over) ..."
bash "$HERE/06_replica_demo.sh" 2>&1 | tee "$HERE/replication_output.log"

echo "============================================================"
echo " Portfolio 5 complete. Evidence: p5_output.log, replication_output.log"
echo " Read 05_cloud_architecture.md for the NDPA 2023 / CAP / cloud discussion."
echo "============================================================"
