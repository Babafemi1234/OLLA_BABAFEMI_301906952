#!/usr/bin/env bash
# =============================================================================
# run_p4.sh  —  Portfolio 4 (NoSQL and Advanced Data Models) runner
# MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111
#
# Assumes Portfolio 1 has run (PostgreSQL has 50k+ orders / ~150k order_items).
# Assumes setup.sh has started MongoDB 8.
#
# Steps:
#   1. 01_schema_validation.js — drop/recreate the garments collection with a
#        $jsonSchema validator (per-garment-type `care` flexibility).
#   2. 02_seed_mongo.py         — build 40,000+ garment documents from the
#        PostgreSQL order_item rows (photos, stains, fabric, per-type care,
#        damage complaints) and bulk-insert into MongoDB.
#   3. 03_aggregations.js      — three aggregations (most common stains, care
#        requests per fabric, damage complaints per outlet).
#   4. 04_index_demo.js        — COLLSCAN -> IXSCAN on {garment_type}.
# =============================================================================

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

# Pick a Mongo URI. setup.sh starts mongod without auth by default in
# Codespaces; if you enabled auth, export MONGO_URI before running.
MONGO_URI="${MONGO_URI:-mongodb://127.0.0.1:27017/freshfold}"

echo "============================================================"
echo " Portfolio 4 — NoSQL and Advanced Data Models (MongoDB)"
echo "============================================================"

echo "[1/4] Creating the garments collection with \$jsonSchema validator ..."
mongosh "$MONGO_URI" "$HERE/01_schema_validation.js"

echo "[2/4] Seeding 40,000+ garment documents from PostgreSQL ..."
python3 "$HERE/02_seed_mongo.py"

echo "[3/4] Running aggregations ..."
mongosh "$MONGO_URI" "$HERE/03_aggregations.js"

echo "[4/4] COLLSCAN -> IXSCAN demo ..."
mongosh "$MONGO_URI" "$HERE/04_index_demo.js"

echo "============================================================"
echo " Portfolio 4 complete."
echo " Paste your REAL mongosh output into the LMS evidence and into"
echo " 05_sql_vs_nosql_comparison.md where applicable."
echo "============================================================"
