#!/usr/bin/env bash
# collect_results.sh - gathers the REAL output of your own run into my_results.txt
cd "$(dirname "$0")"
OUT=my_results.txt
P1=portfolio-1-database-design/p1_output.log
P2=portfolio-2-query-optimisation
P3=portfolio-3-transactions-concurrency
P4=portfolio-4-nosql/p4_output.log
P5=portfolio-5-distributed-cloud
sec(){ echo; echo "=================== $1 ==================="; }
{
echo "MY RESULTS - collected $(date)"
sec "P1 - database design (row counts and constraint tests)"
if [ -f "$P1" ]; then
  grep -E "orders +:|order items +:|payments +:|deliveries +:|rider assignments|pickup slots|over capacity" "$P1" | tail -7
  sed -n 's/.*NOTICE:  //p' "$P1" | grep -E "^(PASS|FAIL)"
else echo "(no $P1)"; fi
sec "P2 - query optimisation (before/after, real ms)"
[ -f $P2/explain_summary.txt ] && cat $P2/explain_summary.txt || echo "(no explain_summary.txt)"
sec "P3 - transactions and concurrency (two real sessions)"
[ -f $P3/race_demos_output.log ] && cat $P3/race_demos_output.log || echo "(no race_demos_output.log)"
if [ -f $P3/p3_output.log ]; then sed -n 's/.*NOTICE:  //p' $P3/p3_output.log | grep -E "^Demo"; fi
sec "P4 - MongoDB (documents and COLLSCAN to IXSCAN)"
if [ -f "$P4" ]; then
  grep -E "documents in collection|inserted|Inserted" "$P4" | head -3
  sed -n '/SUMMARY (real numbers/,/Expect BEFORE/p' "$P4" | head -4
else echo "(no $P4)"; fi
sec "P5 - partitioning"
if [ -f $P5/p5_output.log ]; then
  sed -n '/Rows per month/,/Partitions created/p' $P5/p5_output.log | grep -E "^ 20|rows|month"
  grep -E "Execution Time|flat_count|rows_in_default|^ +[0-9]+ +\|" $P5/p5_output.log | tail -8
else echo "(no p5_output.log)"; fi
sec "P5 - replication (primary 5432, replica 5433)"
[ -f $P5/replication_output.log ] && cat $P5/replication_output.log || echo "(no replication_output.log)"
} > $OUT 2>&1
echo "Wrote $(pwd)/$OUT ($(wc -l < $OUT) lines)"
