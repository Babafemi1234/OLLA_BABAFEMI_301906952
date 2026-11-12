-- =============================================================================
-- 02_indexes.sql  —  Portfolio 2 optimisation indexes
-- Portfolio 2 · MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111
--
-- The "before" EXPLAIN ANALYZE runs against the schema with only the basic
-- indexes created in portfolio-1/01_schema.sql. This file adds the optimisation
-- indexes for the 8 analytical queries; run it, then re-run the EXPLAINs to
-- capture the "after" plans.
--
-- All statements are idempotent (CREATE INDEX IF NOT EXISTS), so this file is
-- safe to run repeatedly. If you want a clean "before", drop the indexes first
-- using the DROP block at the bottom of this file.
-- =============================================================================

\set ON_ERROR_STOP on

-- -----------------------------------------------------------------------------
-- Q1 free slots: the inner GROUP-BY on laundry_order(slot_id) is the hot path.
-- A partial index on the non-cancelled orders (the only ones that count) gives
-- the planner a much smaller index to scan and aggregate.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_order_slot_active
    ON laundry_order (slot_id)
    WHERE status <> 'CANCELLED';

-- -----------------------------------------------------------------------------
-- Q2 orders per outlet per month: composite index on (outlet_id, booked_at)
-- lets the aggregation walk a tight, pre-ordered slice per outlet.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_order_outlet_booked
    ON laundry_order (outlet_id, booked_at);

-- -----------------------------------------------------------------------------
-- Q3 revenue per area: index the join payment(order_id) -> laundry_order and
-- the customer's area. The unique index on payment.order_id already exists, so
-- we add a covering index that lets the planner scan payments in order.
-- An index on laundry_order(customer_id) accelerates the customer join.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_order_customer
    ON laundry_order (customer_id);

-- A covering index on payment(amount) WHERE status='paid' supports the SUM.
CREATE INDEX IF NOT EXISTS ix_payment_paid_amount
    ON payment (amount)
    WHERE status = 'paid';

-- -----------------------------------------------------------------------------
-- Q4 turnaround per outlet: index on laundry_order(outlet_id) WHERE
-- status='DELIVERED' plus delivered_at and picked_up_at so the planner can
-- compute the avg from the index-only-eligible slice (the timestamps are
-- already in the row, but the partial index shrinks the scan).
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_order_delivered_outlet
    ON laundry_order (outlet_id, picked_up_at, delivered_at)
    WHERE status = 'DELIVERED';

-- -----------------------------------------------------------------------------
-- Q5 busiest riders: rider_assignment(rider_id) already exists; add a
-- composite (rider_id, kind) so the FILTER aggregates can be served from the
-- index.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_assignment_rider_kind
    ON rider_assignment (rider_id, kind);

-- -----------------------------------------------------------------------------
-- Q6 most common garment types: order_item(garment_type) already exists from
-- the schema. Add a covering index including quantity and line_total so the
-- SUM/COUNT can be done index-only.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_item_garment_cover
    ON order_item (garment_type, quantity, line_total);

-- -----------------------------------------------------------------------------
-- Q7 revenue per payment method: index on payment(method, amount) WHERE paid.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_payment_method_amount
    ON payment (method, amount)
    WHERE status = 'paid';

-- -----------------------------------------------------------------------------
-- Q8 cancellation rate per area: customer(area_id) already indexed; add a
-- composite on laundry_order(customer_id, status) so the per-customer status
-- counts can be served index-only.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_order_customer_status
    ON laundry_order (customer_id, status);

-- =============================================================================
-- Optional: DROP block — run this to remove the optimisation indexes again
-- (handy if you want to re-capture a clean "before" plan).
-- =============================================================================
-- DROP INDEX IF EXISTS ix_order_slot_active;
-- DROP INDEX IF EXISTS ix_order_outlet_booked;
-- DROP INDEX IF EXISTS ix_order_customer;
-- DROP INDEX IF EXISTS ix_payment_paid_amount;
-- DROP INDEX IF EXISTS ix_order_delivered_outlet;
-- DROP INDEX IF EXISTS ix_assignment_rider_kind;
-- DROP INDEX IF EXISTS ix_item_garment_cover;
-- DROP INDEX IF EXISTS ix_payment_method_amount;
-- DROP INDEX IF EXISTS ix_order_customer_status;

\echo 'Optimisation indexes ready (or already present).'
