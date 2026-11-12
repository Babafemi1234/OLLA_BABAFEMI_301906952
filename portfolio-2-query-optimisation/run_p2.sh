#!/usr/bin/env bash
# =============================================================================
# run_p2.sh  —  Portfolio 2 (Query Processing and Optimisation) runner
# MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111
#
# Assumes Portfolio 1 has run (schema + 50k+ orders are loaded).
#
# Steps:
#   1. Run the 8 analytical queries (01_queries.sql) — produces the result sets.
#   2. Print the BEFORE EXPLAIN ANALYZE plans (basic indexes only).
#   3. Apply the optimisation indexes (02_indexes.sql).
#   4. Print the AFTER EXPLAIN ANALYZE plans.
#
# All psql calls go through the Unix socket (host=/var/run/postgresql) so no
# password is needed in Codespaces. See README "Codespaces rules".
# =============================================================================

set -euo pipefail

PSQL="psql -h /var/run/postgresql -U freshfold -d freshfold -v ON_ERROR_STOP=1"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "============================================================"
echo " Portfolio 2 — Query Processing and Optimisation"
echo "============================================================"

echo "[0/4] Resetting: dropping the P2 optimisation indexes so BEFORE is a fair baseline ..."
$PSQL -q -c "DROP INDEX IF EXISTS ix_order_slot_active, ix_order_outlet_booked, ix_order_customer, ix_payment_paid_amount, ix_order_delivered_outlet, ix_assignment_rider_kind, ix_item_garment_cover, ix_payment_method_amount, ix_order_customer_status;" -c "ANALYZE;"

echo "[1/4] Running the 8 analytical queries ..."
$PSQL -f "$HERE/01_queries.sql"

echo "[2/4] BEFORE EXPLAIN ANALYZE (basic indexes only) ..."
$PSQL <<'SQL' | tee "$HERE/explain_before.txt"
\echo '=== Q1 BEFORE ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.slot_id, s.capacity - COALESCE(used.c,0) AS free_spaces
FROM pickup_slot s
LEFT JOIN (SELECT slot_id, count(*) c FROM laundry_order WHERE status<>'CANCELLED' GROUP BY slot_id) used ON used.slot_id=s.slot_id
WHERE s.area_id=1 AND s.slot_date=CURRENT_DATE+7
ORDER BY s.window_start;

\echo '=== Q2 BEFORE ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT out2.name, to_char(date_trunc('month', o.booked_at),'YYYY-MM') AS month, count(*)
FROM laundry_order o JOIN outlet out2 ON out2.outlet_id=o.outlet_id
GROUP BY out2.name, date_trunc('month', o.booked_at)
ORDER BY out2.name, month;

\echo '=== Q3 BEFORE ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT a.name, sum(p.amount) FROM payment p
JOIN laundry_order o ON o.order_id=p.order_id
JOIN customer c ON c.customer_id=o.customer_id
JOIN area a ON a.area_id=c.area_id
WHERE p.status='paid' GROUP BY a.name ORDER BY 2 DESC;

\echo '=== Q4 BEFORE ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT out2.name, avg(o.delivered_at - o.picked_up_at)
FROM laundry_order o JOIN outlet out2 ON out2.outlet_id=o.outlet_id
WHERE o.status='DELIVERED' GROUP BY out2.name ORDER BY 2 DESC;

\echo '=== Q5 BEFORE ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.full_name, count(*) FROM rider_assignment ra JOIN rider r ON r.rider_id=ra.rider_id
GROUP BY r.rider_id, r.full_name ORDER BY count(*) DESC LIMIT 10;

\echo '=== Q6 BEFORE ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT garment_type, sum(quantity), count(*) FROM order_item GROUP BY garment_type ORDER BY 2 DESC;

\echo '=== Q7 BEFORE ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT method, count(*), sum(amount) FROM payment WHERE status='paid' GROUP BY method ORDER BY 3 DESC;

\echo '=== Q8 BEFORE ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT a.name, count(*), count(*) FILTER (WHERE o.status='CANCELLED')
FROM laundry_order o JOIN customer c ON c.customer_id=o.customer_id
JOIN area a ON a.area_id=c.area_id GROUP BY a.name ORDER BY 3 DESC;
\echo '=== Q9 BEFORE (selective: one outlet, last 30 days) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT status, count(*) FROM laundry_order
WHERE outlet_id=1 AND booked_at >= now() - interval '30 days' GROUP BY status;

\echo '=== Q10 BEFORE (selective: one customer) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT status, count(*) FROM laundry_order WHERE customer_id=5 GROUP BY status;
SQL

echo "[3/4] Applying optimisation indexes (02_indexes.sql) + ANALYZE ..."
$PSQL -f "$HERE/02_indexes.sql"
for T in laundry_order order_item payment rider_assignment; do $PSQL -q -c "VACUUM ANALYZE $T"; done

echo "[4/4] AFTER EXPLAIN ANALYZE (with optimisation indexes) ..."
$PSQL <<'SQL' | tee "$HERE/explain_after.txt"
\echo '=== Q1 AFTER ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.slot_id, s.capacity - COALESCE(used.c,0) AS free_spaces
FROM pickup_slot s
LEFT JOIN (SELECT slot_id, count(*) c FROM laundry_order WHERE status<>'CANCELLED' GROUP BY slot_id) used ON used.slot_id=s.slot_id
WHERE s.area_id=1 AND s.slot_date=CURRENT_DATE+7
ORDER BY s.window_start;

\echo '=== Q2 AFTER ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT out2.name, to_char(date_trunc('month', o.booked_at),'YYYY-MM') AS month, count(*)
FROM laundry_order o JOIN outlet out2 ON out2.outlet_id=o.outlet_id
GROUP BY out2.name, date_trunc('month', o.booked_at)
ORDER BY out2.name, month;

\echo '=== Q3 AFTER ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT a.name, sum(p.amount) FROM payment p
JOIN laundry_order o ON o.order_id=p.order_id
JOIN customer c ON c.customer_id=o.customer_id
JOIN area a ON a.area_id=c.area_id
WHERE p.status='paid' GROUP BY a.name ORDER BY 2 DESC;

\echo '=== Q4 AFTER ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT out2.name, avg(o.delivered_at - o.picked_up_at)
FROM laundry_order o JOIN outlet out2 ON out2.outlet_id=o.outlet_id
WHERE o.status='DELIVERED' GROUP BY out2.name ORDER BY 2 DESC;

\echo '=== Q5 AFTER ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.full_name, count(*) FROM rider_assignment ra JOIN rider r ON r.rider_id=ra.rider_id
GROUP BY r.rider_id, r.full_name ORDER BY count(*) DESC LIMIT 10;

\echo '=== Q6 AFTER ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT garment_type, sum(quantity), count(*) FROM order_item GROUP BY garment_type ORDER BY 2 DESC;

\echo '=== Q7 AFTER ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT method, count(*), sum(amount) FROM payment WHERE status='paid' GROUP BY method ORDER BY 3 DESC;

\echo '=== Q8 AFTER ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT a.name, count(*), count(*) FILTER (WHERE o.status='CANCELLED')
FROM laundry_order o JOIN customer c ON c.customer_id=o.customer_id
JOIN area a ON a.area_id=c.area_id GROUP BY a.name ORDER BY 3 DESC;
\echo '=== Q9 AFTER (selective: one outlet, last 30 days) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT status, count(*) FROM laundry_order
WHERE outlet_id=1 AND booked_at >= now() - interval '30 days' GROUP BY status;

\echo '=== Q10 AFTER (selective: one customer) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT status, count(*) FROM laundry_order WHERE customer_id=5 GROUP BY status;
SQL

echo "============================================================"
echo " Portfolio 2 complete."
echo " Paste your real BEFORE and AFTER plans into 03_explain_before_after.md"
echo " and the summary table at the bottom of that file."
echo ""
echo "=== TIMING SUMMARY (real numbers from this run) -> explain_summary.txt ==="
{
  echo "Query | BEFORE ms | AFTER ms | main scan type BEFORE -> AFTER"
  for n in 1 2 3 4 5 6 7 8 9 10; do
    b=$(awk -v q="=== Q$n BEFORE" 'index($0,q)==1{f=1;next} /^=== /{f=0} f&&/Execution Time/{print $3}' "$HERE/explain_before.txt")
    a=$(awk -v q="=== Q$n AFTER" 'index($0,q)==1{f=1;next} /^=== /{f=0} f&&/Execution Time/{print $3}' "$HERE/explain_after.txt")
    sb=$(awk -v q="=== Q$n BEFORE" 'index($0,q)==1{f=1;next} /^=== /{f=0} f&&/Scan on laundry_order|Scan on order_item|Scan on payment|Scan on rider_assignment|Scan using/{match($0,/(Seq Scan|Index Only Scan|Index Scan|Bitmap Heap Scan)/); print substr($0,RSTART,RLENGTH); exit}' "$HERE/explain_before.txt")
    sa=$(awk -v q="=== Q$n AFTER" 'index($0,q)==1{f=1;next} /^=== /{f=0} f&&/Scan on laundry_order|Scan on order_item|Scan on payment|Scan on rider_assignment|Scan using/{match($0,/(Seq Scan|Index Only Scan|Index Scan|Bitmap Heap Scan)/); print substr($0,RSTART,RLENGTH); exit}' "$HERE/explain_after.txt")
    echo "Q$n | ${b:-?} | ${a:-?} | ${sb:-?} -> ${sa:-?}"
  done
  echo ""
  echo "Note: Q2-Q8 read the whole history, so an index cannot help much and the planner correctly keeps"
  echo "Seq Scan; run-to-run noise of a few ms is normal. Q9 and Q10 are selective, which is where indexes win."
} | tee "$HERE/explain_summary.txt"
echo "============================================================"
