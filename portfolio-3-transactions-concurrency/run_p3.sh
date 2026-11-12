#!/usr/bin/env bash
# =============================================================================
# run_p3.sh  —  Portfolio 3 (Transactions and Concurrency) runner
# MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111
#
# Runs the SINGLE-SESSION parts of Portfolio 3 automatically:
#   1. 01_book_pickup_function.sql  — defines book_pickup() and book_pickup_naive()
#   2. 02_commit_rollback_demo.sql   — COMMIT / ROLLBACK / failed-payment-cancels-order
#
# The TWO-TERMINAL parts (race condition, isolation levels, deadlock) need two
# interactive psql sessions and are documented as step-by-step guides. This
# script prints the exact commands to open the two sessions and the files to
# follow.
#
# All psql calls go through the Unix socket (host=/var/run/postgresql) so no
# password is needed in Codespaces. See README "Codespaces rules".
# =============================================================================

set -euo pipefail

PSQL="psql -h /var/run/postgresql -U freshfold -d freshfold -v ON_ERROR_STOP=1"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "============================================================"
echo " Portfolio 3 — Transactions and Concurrency"
echo "============================================================"

echo "[1/3] Defining book_pickup() + book_pickup_naive() ..."
$PSQL -f "$HERE/01_book_pickup_function.sql"

echo "[2/3] Running COMMIT/ROLLBACK demo ..."
$PSQL -f "$HERE/02_commit_rollback_demo.sql"

echo "[3/3] Preparing the two-terminal race fixture ..."
$PSQL -f "$HERE/00_race_setup.sql"

echo "[3b/3] Running the two-session concurrency demos (race, FOR UPDATE, SERIALIZABLE, deadlock) ..."
python3 "$HERE/run_race_demos.py" 2>&1 | tee "$HERE/race_demos_output.log"

echo "============================================================"
echo " Portfolio 3 complete. Real output saved in race_demos_output.log"
echo "============================================================"
