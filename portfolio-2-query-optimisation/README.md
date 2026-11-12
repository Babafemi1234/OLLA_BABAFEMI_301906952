# Portfolio 2 — Query Processing and Optimisation

**Student:** Olla Babafemi · **Matric:** 2026/A/MIT/0111 · **Course:** MIT 8103 Advanced Database Systems
**Case study:** FreshFold Laundry (Lagos) · **Study session covered:** Study Session 4 — *Query Optimisation in Database*.

## What this portfolio demonstrates

Eight analytical queries on the FreshFold Laundry database — the kind a
manager would actually run — captured with `EXPLAIN (ANALYZE, BUFFERS)`
**before** any optimisation indexes and **after** adding query-specific
indexes, then compared in a before/after table. The point is to show that
the choice of access path (Seq Scan vs Index Scan vs Index-Only Scan), the
join order, and the use of partial / covering indexes is something a database
designer controls, and that the planner's cost model reflects that.

The eight queries answer real operational questions:

1. **Free pickup slots** in Lekki for a date (capacity minus non-cancelled orders).
2. **Orders per outlet per month** — the operational dashboard.
3. **Revenue per area** — paid payments attributed to the customer's area.
4. **Average turnaround time** (pickup → delivery) per outlet.
5. **Busiest riders** — top 10 by total assignments, split pickup vs delivery.
6. **Most common garment types** — by quantity and by revenue.
7. **Revenue per payment method** — card / transfer / cash / USSD.
8. **Cancellation rate per area**.

## Files in this folder

| File | Purpose |
| --- | --- |
| `01_queries.sql` | The 8 analytical queries (runnable directly with `psql`). |
| `02_indexes.sql` | The optimisation indexes (partial, composite, covering). Idempotent. |
| `03_explain_before_after.md` | The before/after `EXPLAIN (ANALYZE, BUFFERS)` plan placeholders and the summary table. **Paste your real plans here.** |
| `run_p2.sh` | Runs the queries, captures the BEFORE plans, applies the indexes, runs ANALYZE, captures the AFTER plans. |

## Exact Codespaces commands

```bash
# from the repository root, after Portfolio 1 has run:
cd advanced-database-portfolio
./portfolio-2-query-optimisation/run_p2.sh
```

Or step by step:

```bash
cd advanced-database-portfolio/portfolio-2-query-optimisation

# 1. run the 8 analytical queries and see the result sets
psql -h /var/run/postgresql -U freshfold -d freshfold -v ON_ERROR_STOP=1 -f 01_queries.sql

# 2. capture the BEFORE plans (run the EXPLAIN block in run_p2.sh, or paste
#    from 03_explain_before_after.md "How to reproduce")

# 3. apply the optimisation indexes and refresh planner statistics
psql -h /var/run/postgresql -U freshfold -d freshfold -v ON_ERROR_STOP=1 -f 02_indexes.sql
psql -h /var/run/postgresql -U freshfold -d freshfold -v ON_ERROR_STOP=1 \
     -c "ANALYZE laundry_order; ANALYZE order_item; ANALYZE payment; ANALYZE rider_assignment;"

# 4. capture the AFTER plans (re-run the EXPLAIN block)
```

## What to screenshot (for the LMS submission evidence)

1. The result set of each of the 8 queries (the `01_queries.sql` output).
2. The BEFORE `EXPLAIN (ANALYZE)` plan for at least Q1, Q2, Q4 and Q6 (show the
   `Seq Scan` / `Hash Aggregate` nodes and the `Execution Time` line).
3. The AFTER `EXPLAIN (ANALYZE)` plan for the same queries (show the
   `Index Scan` / `Index Only Scan` / `Bitmap Heap Scan` nodes and the new
   `Execution Time` line).
4. The completed before/after summary table at the bottom of
   `03_explain_before_after.md` with your real execution times.

> **Honesty rule.** Every `[paste real result here]` and `[paste real result]`
> slot in `03_explain_before_after.md` must be filled with your own captured
> output. Never invent a plan, a cost, or a duration. The summary table's
> `Speed-up` column is derived from your two real timings.

## git commit (run from the repository root)

```bash
git add portfolio-2-query-optimisation/
git commit -m "Portfolio 2: 8 analytical queries, EXPLAIN ANALYZE before/after indexes, optimisation indexes"
git push
```

## Plain-English explanation

The FreshFold database has 50,000+ orders, ~150,000 order items, ~50,000
payments and ~90,000 rider assignments. Without indexes, every analytical
query has to read a whole table from disk and aggregate it in memory — a
Seq Scan plus a Hash Aggregate. That works, but it is wasteful: the same
aggregations run every time a manager opens the dashboard.

For each query we add the smallest index that lets the planner avoid reading
the whole table:

* **Partial indexes** shrink the scan to the rows that actually matter. The
  free-slots query only counts non-cancelled orders, so
  `ix_order_slot_active ... WHERE status <> 'CANCELLED'` indexes just those
  rows. The revenue queries only count paid payments, so
  `ix_payment_paid_amount ... WHERE status = 'paid'` and
  `ix_payment_method_amount ... WHERE status = 'paid'` do the same.
* **Composite / covering indexes** let the aggregation be served almost
  entirely from the index. `ix_order_outlet_booked (outlet_id, booked_at)`
  gives Q2 a tight, pre-ordered slice per outlet; `ix_item_garment_cover
  (garment_type, quantity, line_total)` lets Q6 do the `SUM`/`COUNT`
  index-only (when the visibility map allows).
* **The planner's cost model** decides Seq Scan vs Index Scan based on the
  row count and the selectivity. After `ANALYZE` refreshes the statistics,
  the planner can see that the partial index is tiny and pick it.

The `EXPLAIN (ANALYZE, BUFFERS)` plans show this concretely: BEFORE shows a
`Seq Scan` reading the full table plus a `Hash Aggregate`; AFTER shows an
`Index Scan` or `Index Only Scan` reading only the matching rows. The
`Execution Time` line at the top of each plan is the number we compare in
the before/after table.

## Study session mapping

This portfolio applies **Study Session 4 (Query Optimisation in Database)**:
* section 4.1.2 — Introduction to query optimisation (seq vs index scan,
  join order, the planner's cost model),
* section 4.1.3 — Query execution plans and cost estimation (the
  `EXPLAIN (ANALYZE, BUFFERS)` output, the `cost=... rows=...` and
  `Execution Time` lines),
* section 4.2.1 — File organisation in databases (why B-tree, partial and
  covering indexes change the access path is a file-organisation question).
