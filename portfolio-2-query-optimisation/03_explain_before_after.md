# Portfolio 2 — EXPLAIN ANALYZE: before and after indexing

**Student:** Olla Babafemi · **Matric:** 2026/A/MIT/0111 · **Course:** MIT 8103 Advanced Database Systems
**Case study:** FreshFold Laundry (Lagos) · **Study session covered:** Study Session 4 — *Query Optimisation in Database* (query optimisation, query execution plans and cost estimation, file organisation).

> **Honesty rule.** This document does NOT contain any pre-written `EXPLAIN`
> plans, row counts or timings. Each plan slot is a placeholder
> **`[paste real result here]`**. You must run the commands yourself in
> Codespaces and paste your real captured output. Never invent or simulate an
> execution plan, a cost, or a duration.

## How to reproduce (exact Codespaces commands)

After Portfolio 1 has loaded the 50k+ orders, run, in order:

```bash
cd advanced-database-portfolio/portfolio-2-query-optimisation

# ---- "before" plans: the schema has only the basic indexes from P1
for q in 01_queries.sql; do
  psql -h /var/run/postgresql -U freshfold -d freshfold -v ON_ERROR_STOP=1 \
       -c "SET enable_seqscan = on;" -f $q
done

# Capture the BEFORE EXPLAIN ANALYZE for each query:
psql -h /var/run/postgresql -U freshfold -d freshfold -v ON_ERROR_STOP=1 <<'SQL'
\echo '=== Q1 BEFORE ==='; EXPLAIN (ANALYZE, BUFFERS)
SELECT s.slot_id, s.capacity - COALESCE(used.c,0) AS free_spaces
FROM pickup_slot s
LEFT JOIN (SELECT slot_id, count(*) c FROM laundry_order WHERE status<>'CANCELLED' GROUP BY slot_id) used ON used.slot_id=s.slot_id
WHERE s.area_id=1 AND s.slot_date=CURRENT_DATE+7
ORDER BY s.window_start;

\echo '=== Q2 BEFORE ==='; EXPLAIN (ANALYZE, BUFFERS)
SELECT out2.name, to_char(date_trunc('month', o.booked_at),'YYYY-MM') AS month, count(*)
FROM laundry_order o JOIN outlet out2 ON out2.outlet_id=o.outlet_id
GROUP BY out2.name, date_trunc('month', o.booked_at)
ORDER BY out2.name, month;

\echo '=== Q3 BEFORE ==='; EXPLAIN (ANALYZE, BUFFERS)
SELECT a.name, sum(p.amount) FROM payment p
JOIN laundry_order o ON o.order_id=p.order_id
JOIN customer c ON c.customer_id=o.customer_id
JOIN area a ON a.area_id=c.area_id
WHERE p.status='paid' GROUP BY a.name ORDER BY 2 DESC;

\echo '=== Q4 BEFORE ==='; EXPLAIN (ANALYZE, BUFFERS)
SELECT out2.name, avg(o.delivered_at - o.picked_up_at)
FROM laundry_order o JOIN outlet out2 ON out2.outlet_id=o.outlet_id
WHERE o.status='DELIVERED' GROUP BY out2.name ORDER BY 2 DESC;

\echo '=== Q5 BEFORE ==='; EXPLAIN (ANALYZE, BUFFERS)
SELECT r.full_name, count(*) FROM rider_assignment ra JOIN rider r ON r.rider_id=ra.rider_id
GROUP BY r.rider_id, r.full_name ORDER BY count(*) DESC LIMIT 10;

\echo '=== Q6 BEFORE ==='; EXPLAIN (ANALYZE, BUFFERS)
SELECT garment_type, sum(quantity), count(*) FROM order_item GROUP BY garment_type ORDER BY 2 DESC;

\echo '=== Q7 BEFORE ==='; EXPLAIN (ANALYZE, BUFFERS)
SELECT method, count(*), sum(amount) FROM payment WHERE status='paid' GROUP BY method ORDER BY 3 DESC;

\echo '=== Q8 BEFORE ==='; EXPLAIN (ANALYZE, BUFFERS)
SELECT a.name, count(*), count(*) FILTER (WHERE o.status='CANCELLED')
FROM laundry_order o JOIN customer c ON c.customer_id=o.customer_id
JOIN area a ON a.area_id=c.area_id GROUP BY a.name ORDER BY 3 DESC;
SQL

# ---- add the optimisation indexes
psql -h /var/run/postgresql -U freshfold -d freshfold -v ON_ERROR_STOP=1 -f 02_indexes.sql

# ---- re-run the EXPLAIN ANALYZE block above; capture as the AFTER plans.
# (Re-run the same heredoc; paste the results into the AFTER placeholders below.)
```

Then re-run the same `EXPLAIN (ANALYZE)` block once more, *after* applying
`02_indexes.sql`, and paste those plans into the AFTER placeholders.

After both sets are captured, also run `ANALYZE laundry_order; ANALYZE order_item;
ANALYZE payment; ANALYZE rider_assignment;` so the planner has fresh statistics
before you capture the AFTER plans.

---

## Q1 — Free pickup slots in an area for a date

### BEFORE (basic indexes only)
```
[paste real result here]
```

### AFTER (with `ix_order_slot_active` partial index)
```
[paste real result here]
```

---

## Q2 — Orders per outlet per month

### BEFORE
```
[paste real result here]
```

### AFTER (with `ix_order_outlet_booked`)
```
[paste real result here]
```

---

## Q3 — Revenue per area

### BEFORE
```
[paste real result here]
```

### AFTER (with `ix_order_customer`, `ix_payment_paid_amount`)
```
[paste real result here]
```

---

## Q4 — Average turnaround time per outlet

### BEFORE
```
[paste real result here]
```

### AFTER (with `ix_order_delivered_outlet`)
```
[paste real result here]
```

---

## Q5 — Busiest riders

### BEFORE
```
[paste real result here]
```

### AFTER (with `ix_assignment_rider_kind`)
```
[paste real result here]
```

---

## Q6 — Most common garment types

### BEFORE
```
[paste real result here]
```

### AFTER (with `ix_item_garment_cover`)
```
[paste real result here]
```

---

## Q7 — Revenue per payment method

### BEFORE
```
[paste real result here]
```

### AFTER (with `ix_payment_method_amount`)
```
[paste real result here]
```

---

## Q8 — Cancellation rate per area

### BEFORE
```
[paste real result here]
```

### AFTER (with `ix_order_customer_status`)
```
[paste real result here]
```

---

## Before / after summary table

Fill in the **Execution Time** line at the top of each `EXPLAIN ANALYZE` plan
(it reads something like `Execution Time: 123.456 ms`). Do not invent numbers.

| Query | Description | Index added | BEFORE exec time (ms) | AFTER exec time (ms) | BEFORE plan shape | AFTER plan shape | Speed-up |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Q1 | Free slots in Lekki for a date | `ix_order_slot_active` (partial) | [paste real result] | [paste real result] | [paste: e.g. Seq Scan on laundry_order + Hash Aggregate] | [paste: e.g. Index Only Scan on ix_order_slot_active] | [paste: x.y× faster] |
| Q2 | Orders per outlet per month | `ix_order_outlet_booked` | [paste real result] | [paste real result] | [paste] | [paste] | [paste] |
| Q3 | Revenue per area | `ix_order_customer`, `ix_payment_paid_amount` | [paste real result] | [paste real result] | [paste] | [paste] | [paste] |
| Q4 | Avg turnaround per outlet | `ix_order_delivered_outlet` (partial) | [paste real result] | [paste real result] | [paste] | [paste] | [paste] |
| Q5 | Busiest riders | `ix_assignment_rider_kind` | [paste real result] | [paste real result] | [paste] | [paste] | [paste] |
| Q6 | Most common garment types | `ix_item_garment_cover` | [paste real result] | [paste real result] | [paste] | [paste] | [paste] |
| Q7 | Revenue per payment method | `ix_payment_method_amount` (partial) | [paste real result] | [paste real result] | [paste] | [paste] | [paste] |
| Q8 | Cancellation rate per area | `ix_order_customer_status` | [paste real result] | [paste real result] | [paste] | [paste] | [paste] |

## Notes for the written reflection (fill in after you have real numbers)

* Which query improved the most, and which index was responsible?
  `[write after you have real results]`
* Which query barely improved? Was the planner already using a good plan, or
  did the table fit in memory so the Seq Scan was already cheap?
  `[write after you have real results]`
* Did any partial index (`WHERE status='paid'`, `WHERE status='DELIVERED'`,
  `WHERE status <> 'CANCELLED'`) shrink the scanned rows dramatically?
  `[write after you have real results]`
* Did you observe an Index-Only Scan anywhere? Why / why not (visibility map,
  covering columns)?
  `[write after you have real results]`

## Study session mapping

This portfolio applies **Study Session 4 (Query Optimisation in Database)**:
* section 4.1.2 — Introduction to query optimisation (choosing seq vs index
  scans, join orders),
* section 4.1.3 — Query execution plans and cost estimation (the
  `EXPLAIN (ANALYZE, BUFFERS)` plans above, the cost numbers and the execution
  times),
* section 4.2.1 — File organisation in databases (which underlies why B-tree
  indexes, partial indexes and covering indexes change the access path).
