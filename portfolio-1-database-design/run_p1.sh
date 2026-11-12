#!/usr/bin/env bash
# =============================================================================
# run_p1.sh  —  Portfolio 1 (Database Design) end-to-end runner
# MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111
# Case study: FreshFold Laundry (Lagos)
#
# Runs the whole of Portfolio 1 in order, through the Unix socket (no TCP,
# no password — see README "Codespaces rules"):
#   1. 01_schema.sql             — create the schema (9 core tables + 1 helper,
#                                  constraints, triggers, EXCLUDE on btree_gist)
#   2. 04_seed_data.sql          — seed areas, outlets, 30 customers, 12 riders,
#                                  ~900 starter pickup slots for the next 30 days
#   3. 05_bulk_generator.py      — 50,000+ orders over 2 years, realistic
#                                  Nigerian names / Lagos addresses / ₦ prices,
#                                  no slot over capacity, rider-exclusion-safe
#   4. 06_constraint_tests.sql   — every constraint tested; each MUST be rejected
# =============================================================================

set -euo pipefail

PSQL="psql -h /var/run/postgresql -U freshfold -d freshfold -v ON_ERROR_STOP=1"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "============================================================"
echo " Portfolio 1 — Database Design and Modelling (FreshFold)"
echo "============================================================"

echo "[1/4] Creating schema (01_schema.sql) ..."
$PSQL -f "$HERE/01_schema.sql"

echo "[2/4] Loading seed data (04_seed_data.sql) ..."
$PSQL -f "$HERE/04_seed_data.sql"

echo "[3/4] Generating 50,000+ bulk orders (05_bulk_generator.py) ..."
python3 "$HERE/05_bulk_generator.py"

echo "[4/4] Running constraint tests (06_constraint_tests.sql) ..."
$PSQL -f "$HERE/06_constraint_tests.sql"

echo "============================================================"
echo " Portfolio 1 complete."
echo " Schema, seed data, 50k+ bulk orders and constraint tests are done."
echo " Open 02_er_diagram.md and 03_normalisation_notes.md in GitHub to view"
echo " the ER diagram (Mermaid) and the 3NF explanation."
echo "============================================================"
