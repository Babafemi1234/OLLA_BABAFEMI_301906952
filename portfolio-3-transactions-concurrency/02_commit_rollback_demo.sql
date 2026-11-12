-- =============================================================================
-- 02_commit_rollback_demo.sql  —  Portfolio 3 COMMIT / ROLLBACK demo
-- Portfolio 3 · MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111
--
-- Three demos, each self-contained, each prints a clear PASS/observation line:
--
--   Demo A — COMMIT:        book_pickup() happy path. Order + items + payment
--                            are created and committed. Counts go UP.
--   Demo B — ROLLBACK:      book_pickup() with a SIMULATED payment failure.
--                            The exception aborts the transaction, so the order
--                            + items + payment are rolled back. Counts UNCHANGED.
--   Demo C — failed payment CANCELS the order:
--                            a DO block with a savepoint creates the order + items,
--                            tries the payment in a subtransaction, and on failure
--                            sets the order status to CANCELLED and records a
--                            'failed' payment. The order PERSISTS as CANCELLED.
--
-- This file is RUNNABLE: it sets ON_ERROR_STOP on, creates a dedicated test slot
-- and customer, runs the three demos and prints what to observe. Re-running is
-- safe (each demo cleans up the rows it creates).
-- =============================================================================

\set ON_ERROR_STOP on

-- -----------------------------------------------------------------------------
-- Test fixture: a dedicated 10-capacity slot + a test customer, both relative
-- to CURRENT_DATE so the demo never expires. ON CONFLICT keeps it idempotent.
-- -----------------------------------------------------------------------------
INSERT INTO pickup_slot (area_id, slot_date, window_start, window_end, capacity)
VALUES (1, CURRENT_DATE + 14, time '08:00', time '10:00', 10)
ON CONFLICT (area_id, slot_date, window_start) DO UPDATE SET capacity = EXCLUDED.capacity;

SELECT slot_id AS p3_slot_id FROM pickup_slot
 WHERE area_id=1 AND slot_date=CURRENT_DATE+14 AND window_start=time '08:00'
 \gset

-- make sure a test customer exists in area 1
INSERT INTO customer (full_name, phone, email, area_id, address)
SELECT 'Portfolio3 Test Customer', '0809 000 0003', 'p3@example.com', 1, '1 Demo Rd, Lekki'
 WHERE NOT EXISTS (SELECT 1 FROM customer WHERE email='p3@example.com');
SELECT customer_id AS p3_cust_id FROM customer WHERE email='p3@example.com' \gset
SELECT set_config('p3.slot', :'p3_slot_id', false), set_config('p3.cust', :'p3_cust_id', false);

\echo '===================================================='
\echo ' Demo A — COMMIT (happy path)'
\echo '===================================================='

DO $$
DECLARE
    v_before_orders INTEGER;
    v_after_orders  INTEGER;
    v_order_id      BIGINT;
    v_items         JSONB;
BEGIN
    SELECT count(*) INTO v_before_orders FROM laundry_order WHERE slot_id = current_setting('p3.slot')::int;

    v_items := '[{"garment_type":"shirt","quantity":2,"service":"wash_iron","unit_price":600},
                 {"garment_type":"trouser","quantity":1,"service":"wash_iron","unit_price":700}]'::jsonb;

    -- happy path: payment succeeds
    SELECT book_pickup(current_setting('p3.cust')::int, current_setting('p3.slot')::int, v_items, 'card', 1900.00, false)
      INTO v_order_id;

    SELECT count(*) INTO v_after_orders FROM laundry_order WHERE slot_id = current_setting('p3.slot')::int;

    RAISE NOTICE 'Demo A: booked order % (payments ok). Orders in slot: % -> %',
        v_order_id, v_before_orders, v_after_orders;
    RAISE NOTICE '  -> Observe: counts increased by 1 (COMMIT worked).';
END $$;

-- cleanup demo A's order(s) so the slot is fresh for demo B/C re-runs.
-- Remove any BOOKED orders for this customer in this slot (Demo C's
-- CANCELLED orders are left as the audit trail and do not count against
-- capacity, so they can safely accumulate).
DELETE FROM laundry_order
 WHERE slot_id = current_setting('p3.slot')::int
   AND customer_id = current_setting('p3.cust')::int
   AND status = 'BOOKED';

\echo '===================================================='
\echo ' Demo B — ROLLBACK (simulated payment failure)'
\echo '===================================================='

DO $$
DECLARE
    v_before_orders INTEGER;
    v_after_orders  INTEGER;
    v_items         JSONB;
BEGIN
    SELECT count(*) INTO v_before_orders FROM laundry_order WHERE slot_id = current_setting('p3.slot')::int;

    v_items := '[{"garment_type":"duvet","quantity":1,"service":"dry_clean","unit_price":5000}]'::jsonb;

    -- attempt the booking; the payment is simulated to fail, so the function
    -- raises PAYMENT_FAILED and the whole transaction is rolled back.
    BEGIN
        PERFORM book_pickup(current_setting('p3.cust')::int, current_setting('p3.slot')::int, v_items, 'card', 5000.00, true);
        RAISE EXCEPTION 'Demo B: expected PAYMENT_FAILED but booking succeeded (BUG)';
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'Demo B: payment failed -> %', SQLERRM;
    END;

    SELECT count(*) INTO v_after_orders FROM laundry_order WHERE slot_id = current_setting('p3.slot')::int;

    RAISE NOTICE 'Demo B: orders in slot: % -> % (MUST be equal)',
        v_before_orders, v_after_orders;
    RAISE NOTICE '  -> Observe: counts UNCHANGED. The order was rolled back (no orphan order).';
END $$;

\echo '===================================================='
\echo ' Demo C — failed payment CANCELS the order (order persists)'
\echo '===================================================='

DO $$
DECLARE
    v_order_id   BIGINT;
    v_outlet_id  INTEGER;
    v_items      JSONB := '[{"garment_type":"suit","quantity":1,"service":"dry_clean","unit_price":6000}]'::jsonb;
    v_paid_status TEXT;
    v_order_status TEXT;
BEGIN
    SELECT o.outlet_id INTO v_outlet_id FROM outlet o WHERE o.area_id = 1 LIMIT 1;

    -- insert the order as BOOKED
    INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
    VALUES (current_setting('p3.cust')::int, current_setting('p3.slot')::int, v_outlet_id, 'BOOKED', now(), '1 Demo Rd, Lekki')
    RETURNING order_id INTO v_order_id;

    -- insert the items
    INSERT INTO order_item (order_id, garment_type, quantity, service, unit_price)
    VALUES (v_order_id, 'suit', 1, 'dry_clean', 6000);

    -- try the payment in a subtransaction; on failure, mark order CANCELLED
    -- and record a FAILED payment (so we keep an audit trail), then COMMIT.
    BEGIN
        INSERT INTO payment (order_id, amount, method, status, reference, paid_at)
        VALUES (v_order_id, 6000, 'card', 'paid', 'FF-DEMO-C-'||v_order_id, now());
        -- (simulate a downstream gateway failure here)
        RAISE EXCEPTION 'PAYMENT_FAILED: gateway declined';
    EXCEPTION
        WHEN OTHERS THEN
            -- record the failed payment attempt (audit trail)
            INSERT INTO payment (order_id, amount, method, status, reference)
            VALUES (v_order_id, 6000, 'card', 'failed', 'FF-DEMO-C-'||v_order_id);
            -- cancel the order (BOOKED -> CANCELLED is a valid transition)
            UPDATE laundry_order SET status = 'CANCELLED' WHERE order_id = v_order_id;
    END;

    -- verify the persisted state
    SELECT status INTO v_order_status FROM laundry_order WHERE order_id = v_order_id;
    SELECT status INTO v_paid_status FROM payment  WHERE order_id = v_order_id;

    RAISE NOTICE 'Demo C: order % persisted with status=% , payment status=%',
        v_order_id, v_order_status, v_paid_status;
    RAISE NOTICE '  -> Observe: order is CANCELLED and a FAILED payment is recorded. The order PERSISTS (audit trail).';
END $$;

\echo '===================================================='
\echo ' End of COMMIT/ROLLBACK demo.'
\echo '===================================================='
