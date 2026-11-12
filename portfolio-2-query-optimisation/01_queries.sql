-- =============================================================================
-- 01_queries.sql  —  Portfolio 2 query workload (8 analytical queries)
-- Portfolio 2 · MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111
-- Case study: FreshFold Laundry (Lagos). All amounts are in Naira (₦).
-- All dates are relative to CURRENT_DATE so the workload never expires.
--
-- These 8 queries are the workload we EXPLAIN ANALYZE before and after adding
-- the optimisation indexes in 02_indexes.sql. Each query is tagged Qn.
-- =============================================================================

\set ON_ERROR_STOP on
\pset pager off
\pset format aligned

-- =============================================================================
-- Q1. Free pickup slots in a given area for a given date
--     (capacity minus non-cancelled orders). Area 1 = Lekki, date = today + 7.
-- =============================================================================
\echo '>> Q1: free pickup slots in Lekki for CURRENT_DATE + 7'
SELECT s.slot_id,
       a.name  AS area,
       s.slot_date,
       s.window_start,
       s.window_end,
       s.capacity,
       s.capacity - COALESCE(used.c, 0) AS free_spaces
FROM   pickup_slot s
JOIN   area a ON a.area_id = s.area_id
LEFT JOIN (
    SELECT slot_id, count(*) AS c
    FROM   laundry_order
    WHERE  status <> 'CANCELLED'
    GROUP BY slot_id
) used ON used.slot_id = s.slot_id
WHERE  s.area_id = 1
  AND  s.slot_date = CURRENT_DATE + 7
  AND  s.capacity - COALESCE(used.c, 0) > 0
ORDER BY s.window_start;

-- =============================================================================
-- Q2. Orders per outlet per month (the operational dashboard view)
-- =============================================================================
\echo '>> Q2: orders per outlet per month'
SELECT out2.name AS outlet,
       to_char(date_trunc('month', o.booked_at), 'YYYY-MM') AS month,
       count(*) AS orders
FROM   laundry_order o
JOIN   outlet out2 ON out2.outlet_id = o.outlet_id
GROUP BY out2.name, date_trunc('month', o.booked_at)
ORDER BY out2.name, month;

-- =============================================================================
-- Q3. Revenue per area (sum of PAID payments, attributed to the customer's area)
-- =============================================================================
\echo '>> Q3: revenue per area (paid payments)'
SELECT a.name AS area,
       sum(p.amount) AS revenue_ngn,
       count(*)     AS paid_payments
FROM   payment p
JOIN   laundry_order o ON o.order_id = p.order_id
JOIN   customer     c ON c.customer_id = o.customer_id
JOIN   area         a ON a.area_id = c.area_id
WHERE  p.status = 'paid'
GROUP BY a.name
ORDER BY revenue_ngn DESC;

-- =============================================================================
-- Q4. Average turnaround time (pickup -> delivery) per outlet
-- =============================================================================
\echo '>> Q4: average turnaround time per outlet'
SELECT out2.name AS outlet,
       count(*)                                            AS delivered_orders,
       round(extract(epoch FROM avg(o.delivered_at - o.picked_up_at))/3600.0, 2)
                                                            AS avg_turnaround_hours,
       round(extract(epoch FROM percentile_cont(0.5)
                     WITHIN GROUP (ORDER BY (o.delivered_at - o.picked_up_at)))/3600.0, 2)
                                                            AS median_turnaround_hours
FROM   laundry_order o
JOIN   outlet out2 ON out2.outlet_id = o.outlet_id
WHERE  o.status = 'DELIVERED'
GROUP BY out2.name
ORDER BY avg_turnaround_hours DESC;

-- =============================================================================
-- Q5. Busiest riders (most assignments, split by kind)
-- =============================================================================
\echo '>> Q5: busiest riders (top 10 by total assignments)'
SELECT r.full_name,
       r.vehicle,
       count(*) FILTER (WHERE ra.kind = 'pickup')   AS pickups,
       count(*) FILTER (WHERE ra.kind = 'delivery')  AS deliveries,
       count(*)                                       AS total_assignments
FROM   rider_assignment ra
JOIN   rider r ON r.rider_id = ra.rider_id
GROUP BY r.rider_id, r.full_name, r.vehicle
ORDER BY total_assignments DESC
LIMIT 10;

-- =============================================================================
-- Q6. Most common garment types (by quantity washed, and the revenue they earn)
-- =============================================================================
\echo '>> Q6: most common garment types'
SELECT garment_type,
       sum(quantity)     AS total_qty,
       count(*)          AS line_count,
       sum(line_total)   AS revenue_ngn
FROM   order_item
GROUP BY garment_type
ORDER BY total_qty DESC;

-- =============================================================================
-- Q7. Revenue per payment method
-- =============================================================================
\echo '>> Q7: revenue per payment method'
SELECT method,
       count(*)     AS payments,
       sum(amount)  AS revenue_ngn,
       round(avg(amount), 2) AS avg_amount
FROM   payment
WHERE  status = 'paid'
GROUP BY method
ORDER BY revenue_ngn DESC;

-- =============================================================================
-- Q8. Cancellation rate per area
-- =============================================================================
\echo '>> Q8: cancellation rate per area'
SELECT a.name AS area,
       count(*)                                                   AS total_orders,
       count(*) FILTER (WHERE o.status = 'CANCELLED')             AS cancelled,
       round(100.0 * count(*) FILTER (WHERE o.status = 'CANCELLED') / count(*), 2)
                                                                 AS cancel_pct
FROM   laundry_order o
JOIN   customer c ON c.customer_id = o.customer_id
JOIN   area     a ON a.area_id = c.area_id
GROUP BY a.name
ORDER BY cancel_pct DESC;
