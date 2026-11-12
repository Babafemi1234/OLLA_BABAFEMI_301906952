-- =============================================================================
-- 01_partitioning.sql  —  Portfolio 5 declarative partitioning
-- Portfolio 5 · MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111
-- Case study: FreshFold Laundry (Lagos)
--
-- Partitions the orders table BY MONTH using PostgreSQL declarative
-- RANGE partitioning on booked_at. We create a parallel partitioned table
-- `laundry_order_p` (same shape as `laundry_order`), build monthly partitions
-- across the 2-year data span + a 12-month forward margin + a default
-- partition, migrate the data from the flat `laundry_order`, and demonstrate
-- PARTITION PRUNING with EXPLAIN.
--
-- Why a parallel table (laundry_order_p) and not in-place conversion?
--   A partitioned table's PRIMARY KEY / UNIQUE constraints must include the
--   partition key (booked_at). The FK graph in Portfolio 1 (order_item,
--   payment, delivery, rider_assignment -> laundry_order.order_id) relies on
--   order_id being unique on its own. Re-pointing every FK to a composite
--   (order_id, booked_at) would mean adding booked_at to every child table,
--   which is invasive and distracts from the partitioning lesson. We therefore
--   demonstrate partitioning on a parallel copy, exactly as a migration plan
--   would stage it, and document the FK caveat below.
--
-- All dates are relative to CURRENT_DATE so the partitions stay aligned with
-- the data over time.
-- =============================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS laundry_order_p CASCADE;

-- -----------------------------------------------------------------------------
-- 1. The partitioned parent. PK must include the partition key (booked_at).
--    Same columns + constraints as the flat laundry_order.
-- -----------------------------------------------------------------------------
CREATE TABLE laundry_order_p (
    order_id          BIGSERIAL,
    customer_id       INTEGER NOT NULL,
    slot_id           INTEGER NOT NULL,
    outlet_id         INTEGER NOT NULL,
    pickup_rider_id   INTEGER,
    delivery_rider_id INTEGER,
    status            TEXT NOT NULL DEFAULT 'BOOKED'
                        CHECK (status IN
                          ('BOOKED','PICKED_UP','WASHING','READY','DELIVERED','CANCELLED')),
    booked_at         timestamptz NOT NULL DEFAULT now(),
    picked_up_at      timestamptz,
    washing_started_at timestamptz,
    ready_at          timestamptz,
    delivered_at     timestamptz,
    delivery_address  TEXT NOT NULL,
    created_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_p_delivery_after_pickup
        CHECK (delivered_at IS NULL OR picked_up_at IS NULL OR delivered_at > picked_up_at),
    CONSTRAINT chk_p_washing_after_pickup
        CHECK (washing_started_at IS NULL OR picked_up_at IS NULL OR washing_started_at >= picked_up_at),
    CONSTRAINT chk_p_ready_after_washing
        CHECK (ready_at IS NULL OR washing_started_at IS NULL OR ready_at >= washing_started_at),
    CONSTRAINT chk_p_delivered_after_ready
        CHECK (delivered_at IS NULL OR ready_at IS NULL OR delivered_at >= ready_at),
    -- partitioned PK must include booked_at
    PRIMARY KEY (order_id, booked_at)
) PARTITION BY RANGE (booked_at);

-- -----------------------------------------------------------------------------
-- 2. Monthly partitions: from CURRENT_DATE - 24 months to CURRENT_DATE + 12
--    months (37 partitions) + a default partition for anything outside.
--    Using generate_series relative to CURRENT_DATE so the partition set
--    never "expires" relative to the data.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    m DATE;
    part_start DATE;
    part_end   DATE;
    part_name  TEXT;
BEGIN
    -- start of the month 24 months ago
    m := date_trunc('month', CURRENT_DATE - interval '24 months')::date;
    WHILE m <= date_trunc('month', CURRENT_DATE + interval '12 months')::date LOOP
        part_start := m;
        part_end   := (m + interval '1 month')::date;
        part_name  := 'laundry_order_p_' || to_char(m, 'YYYYMM');
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF laundry_order_p FOR VALUES FROM (%L) TO (%L)',
            part_name, part_start, part_end);
        m := part_end;
    END LOOP;
END $$;

-- default partition catches any row outside the explicit monthly partitions
CREATE TABLE laundry_order_p_default PARTITION OF laundry_order_p DEFAULT;

-- -----------------------------------------------------------------------------
-- 3. Migrate the data from the flat table (ordered by booked_at so the
--    partitions fill in chronological order, which keeps the indexes cheap).
-- -----------------------------------------------------------------------------
INSERT INTO laundry_order_p
       (order_id, customer_id, slot_id, outlet_id, pickup_rider_id,
        delivery_rider_id, status, booked_at, picked_up_at,
        washing_started_at, ready_at, delivered_at, delivery_address, created_at)
SELECT order_id, customer_id, slot_id, outlet_id, pickup_rider_id,
       delivery_rider_id, status, booked_at, picked_up_at,
       washing_started_at, ready_at, delivered_at, delivery_address, created_at
FROM   laundry_order
ORDER BY booked_at;

-- a couple of useful indexes on the parent (applied to every partition)
CREATE INDEX ix_p_order_outlet   ON laundry_order_p (outlet_id);
CREATE INDEX ix_p_order_status  ON laundry_order_p (status);
CREATE INDEX ix_p_order_slot    ON laundry_order_p (slot_id);

-- -----------------------------------------------------------------------------
-- 4. Report: rows per month across the partitioned table (proves the data is
--    split by month). This counts the actual rows, so it is accurate even
--    before ANALYZE.
-- -----------------------------------------------------------------------------
\echo '===================================================='
\echo ' Rows per month in the partitioned table (laundry_order_p)'
\echo '===================================================='
SELECT to_char(date_trunc('month', booked_at), 'YYYY-MM') AS month,
       count(*) AS rows
FROM   laundry_order_p
GROUP BY 1
ORDER BY 1;
\echo ''

-- List the partitions and their bounds (shows the partition set)
\echo '----------------------------------------------------'
\echo ' Partitions created:'
\echo '----------------------------------------------------'
SELECT c.relname AS partition,
       pg_get_expr(c.relpartbound, c.oid) AS bound
FROM   pg_inherits i
JOIN   pg_class c ON c.oid = i.inhrelid
WHERE  i.inhparent = 'laundry_order_p'::regclass
ORDER BY c.relname;
\echo ''

-- -----------------------------------------------------------------------------
-- 5. PARTITION PRUNING demonstration.
--    A query restricted to a narrow month range should touch ONLY the relevant
--    partition(s), not the whole table. Run EXPLAIN and observe "Subplans
--    Removed" or that only the matching partition appears in the plan.
-- -----------------------------------------------------------------------------
\echo '===================================================='
\echo ' Partition pruning EXPLAIN (only the last 3 months scanned)'
\echo '===================================================='
EXPLAIN (ANALYZE, BUFFERS, SUMMARY)
SELECT count(*), sum(amount)
FROM   laundry_order_p p
JOIN   payment pt ON pt.order_id = p.order_id
WHERE  p.booked_at >= date_trunc('month', CURRENT_DATE - interval '3 months')
  AND  p.booked_at <  date_trunc('month', CURRENT_DATE);
\echo ''

\echo '===================================================='
\echo ' Full-scan EXPLAIN (no date filter -> scans every partition)'
\echo '===================================================='
EXPLAIN (ANALYZE, BUFFERS, SUMMARY)
SELECT count(*) FROM laundry_order_p;
\echo ''

\echo '===================================================='
\echo ' Compare row counts: flat vs partitioned (must match)'
\echo '===================================================='
SELECT (SELECT count(*) FROM laundry_order)   AS flat_count,
       (SELECT count(*) FROM laundry_order_p) AS partitioned_count;
\echo ''

\echo 'Rows that fell into the DEFAULT partition (must be 0):'
SELECT count(*) AS rows_in_default_partition FROM laundry_order_p_default;

\echo '===================================================='
\echo ' Partitioning demo complete.'
\echo ' Paste your real EXPLAIN plans + the per-partition row'
\echo ' counts into the LMS evidence.'
\echo '===================================================='
