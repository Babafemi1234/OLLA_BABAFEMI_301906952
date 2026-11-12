-- =============================================================================
-- 06_constraint_tests.sql  —  Portfolio 1 constraint tests
-- Portfolio 1 · MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111
--
-- Every constraint in the schema is tested here. Each test performs an
-- INVALID operation inside a PL/pgSQL subtransaction (BEGIN ... EXCEPTION).
-- If the constraint correctly rejects the operation, we raise a NOTICE
-- "PASS". If the operation wrongly succeeds, we raise an EXCEPTION "FAIL".
--
-- So this script RUNS successfully and prints a PASS/FAIL report; the "must
-- fail" behaviour is the constraint rejecting each bad operation, which we
-- assert by catching the exception.
--
-- IMPORTANT: each test uses a far-future date (CURRENT_DATE + 41 .. + 52),
-- which is OUTSIDE the seed's 30-day window and the bulk generator's +7-day
-- window, so the test slots never collide with real data. A cleanup block at
-- the top makes the whole file idempotent (safe to re-run).
--
-- Run with:  psql -h /var/run/postgresql -U freshfold -d freshfold -f 06_constraint_tests.sql
-- =============================================================================

\set ON_ERROR_STOP on

\echo '=========================================================='
\echo ' Portfolio 1 — constraint tests (each MUST be rejected)'
\echo '=========================================================='

-- -----------------------------------------------------------------------------
-- Cleanup: remove any leftover test rows from a previous run, in the test
-- date range. We delete orders first (cascades items/payment/delivery/assignment),
-- then the test slots.
-- -----------------------------------------------------------------------------
DELETE FROM laundry_order
 WHERE slot_id IN (SELECT slot_id FROM pickup_slot
                    WHERE slot_date BETWEEN CURRENT_DATE + 40 AND CURRENT_DATE + 60);
DELETE FROM pickup_slot
 WHERE slot_date BETWEEN CURRENT_DATE + 40 AND CURRENT_DATE + 60;

-- ---- Test 1: slot capacity exceeded -------------------------------
DO $$
DECLARE
    slot_id_v INTEGER;
    cust_id   INTEGER;
    v_outlet  INTEGER;
BEGIN
    INSERT INTO pickup_slot (area_id, slot_date, window_start, window_end, capacity)
    VALUES (1, CURRENT_DATE + 41, time '08:00', time '10:00', 2)
    RETURNING slot_id INTO slot_id_v;

    SELECT customer_id INTO cust_id   FROM customer WHERE area_id = 1 LIMIT 1;
    SELECT outlet_id   INTO v_outlet FROM outlet  WHERE area_id = 1 LIMIT 1;

    -- first two bookings: OK
    INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
    VALUES (cust_id, slot_id_v, v_outlet, 'BOOKED', now(), 'T1a, Lekki');
    INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
    VALUES (cust_id, slot_id_v, v_outlet, 'BOOKED', now(), 'T1b, Lekki');

    -- third booking: MUST be rejected by the capacity trigger
    BEGIN
        INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
        VALUES (cust_id, slot_id_v, v_outlet, 'BOOKED', now(), 'T1c, Lekki');
        RAISE EXCEPTION 'FAIL test 1: slot capacity NOT enforced (3rd booking accepted on a 2-cap slot)';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS test 1: slot capacity trigger rejected over-capacity booking';
    END;
END $$;

-- ---- Test 2: same rider double-booked for two overlapping pickups ----
DO $$
DECLARE
    s_lekki INTEGER; s_ikeja INTEGER;
    c1      INTEGER; c2 INTEGER; out_id INTEGER; r_id INTEGER;
BEGIN
    INSERT INTO pickup_slot (area_id, slot_date, window_start, window_end, capacity)
    VALUES (1, CURRENT_DATE + 42, time '10:00', time '12:00', 5);
    INSERT INTO pickup_slot (area_id, slot_date, window_start, window_end, capacity)
    VALUES (2, CURRENT_DATE + 42, time '10:00', time '12:00', 5);

    SELECT slot_id INTO s_lekki FROM pickup_slot
     WHERE area_id=1 AND slot_date=CURRENT_DATE+42 AND window_start=time '10:00';
    SELECT slot_id INTO s_ikeja FROM pickup_slot
     WHERE area_id=2 AND slot_date=CURRENT_DATE+42 AND window_start=time '10:00';

    SELECT customer_id INTO c1 FROM customer WHERE area_id=1 LIMIT 1;
    SELECT customer_id INTO c2 FROM customer WHERE area_id=2 LIMIT 1;
    SELECT outlet_id  INTO out_id FROM outlet WHERE area_id=1 LIMIT 1;
    SELECT rider_id   INTO r_id  FROM rider WHERE home_area_id=1 LIMIT 1;

    -- first order: rider r_id does a pickup in Lekki 10-12 -> ok
    INSERT INTO laundry_order (customer_id, slot_id, outlet_id, pickup_rider_id, status, booked_at, delivery_address)
    VALUES (c1, s_lekki, out_id, r_id, 'BOOKED', now(), 'T2a, Lekki');

    -- second order: SAME rider, Ikeja 10-12 (overlapping window) -> MUST be rejected
    BEGIN
        INSERT INTO laundry_order (customer_id, slot_id, outlet_id, pickup_rider_id, status, booked_at, delivery_address)
        VALUES (c2, s_ikeja, out_id, r_id, 'BOOKED', now(), 'T2b, Ikeja');
        RAISE EXCEPTION 'FAIL test 2: rider exclusion NOT enforced (same rider booked twice in overlapping window)';
    EXCEPTION
        WHEN exclusion_violation THEN
            RAISE NOTICE 'PASS test 2: EXCLUDE constraint rejected overlapping pickup for the same rider';
    END;
END $$;

-- ---- Test 3: rider pickup overlapping a delivery trip ----------------
DO $$
DECLARE
    r_id   INTEGER;
    c1     INTEGER; out_id INTEGER; s_id INTEGER; o_id BIGINT;
BEGIN
    SELECT rider_id INTO r_id FROM rider WHERE rider_id > 40 ORDER BY rider_id LIMIT 1;
    IF r_id IS NULL THEN
        SELECT rider_id INTO r_id FROM rider ORDER BY rider_id DESC LIMIT 1;  -- fallback
    END IF;

    INSERT INTO pickup_slot (area_id, slot_date, window_start, window_end, capacity)
    VALUES (1, CURRENT_DATE + 43, time '14:00', time '16:00', 5)
    RETURNING slot_id INTO s_id;

    SELECT customer_id INTO c1 FROM customer WHERE area_id=1 LIMIT 1;
    SELECT outlet_id  INTO out_id FROM outlet WHERE area_id=1 LIMIT 1;

    -- order with this rider as pickup rider -> pickup assignment on 14:00-16:00
    INSERT INTO laundry_order (customer_id, slot_id, outlet_id, pickup_rider_id, status, booked_at, delivery_address)
    VALUES (c1, s_id, out_id, r_id, 'BOOKED', now(), 'T3, Lekki')
    RETURNING order_id INTO o_id;

    -- try a delivery row for the SAME rider whose trip overlaps 14:30-15:30
    -- (inside the pickup window). sync_delivery inserts a delivery assignment
    -- that overlaps the pickup assignment -> EXCLUDE must reject.
    -- The trip times are built as explicit Lagos timestamptz so the overlap
    -- with the pickup window (also Lagos) is guaranteed regardless of the
    -- session timezone.
    BEGIN
        INSERT INTO delivery (order_id, rider_id, picked_up_at, delivered_at, signature)
        VALUES (o_id, r_id,
                ((CURRENT_DATE + 43) + time '15:00') AT TIME ZONE 'Africa/Lagos',
                ((CURRENT_DATE + 43) + time '15:30') AT TIME ZONE 'Africa/Lagos',
                'overlap test');
        RAISE EXCEPTION 'FAIL test 3: rider exclusion NOT enforced (pickup vs delivery overlap accepted)';
    EXCEPTION
        WHEN exclusion_violation THEN
            RAISE NOTICE 'PASS test 3: EXCLUDE constraint rejected rider pickup vs delivery overlap';
    END;
END $$;

-- ---- Test 4: delivery time NOT after pickup time -------------------
DO $$
DECLARE
    c1 INTEGER; out_id INTEGER; s_id INTEGER; o_id BIGINT; r_id INTEGER;
BEGIN
    INSERT INTO pickup_slot (area_id, slot_date, window_start, window_end, capacity)
    VALUES (1, CURRENT_DATE + 44, time '08:00', time '10:00', 5)
    RETURNING slot_id INTO s_id;
    SELECT customer_id INTO c1 FROM customer WHERE area_id=1 LIMIT 1;
    SELECT outlet_id  INTO out_id FROM outlet WHERE area_id=1 LIMIT 1;
    SELECT rider_id   INTO r_id  FROM rider LIMIT 1;

    INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
    VALUES (c1, s_id, out_id, 'BOOKED', now(), 'T4, Lekki')
    RETURNING order_id INTO o_id;

    BEGIN
        INSERT INTO delivery (order_id, rider_id, picked_up_at, delivered_at, signature)
        VALUES (o_id, r_id,
                (CURRENT_DATE + 44)::timestamp + interval '09:00',
                (CURRENT_DATE + 44)::timestamp + interval '08:30',   -- before pickup!
                'bad');
        RAISE EXCEPTION 'FAIL test 4: delivered_at > picked_up_at NOT enforced';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS test 4: CHECK rejected delivery where delivered_at is before picked_up_at';
    END;
END $$;

-- ---- Test 5: quantity > 0 -----------------------------------------
DO $$
DECLARE
    c1 INTEGER; out_id INTEGER; s_id INTEGER; o_id BIGINT;
BEGIN
    INSERT INTO pickup_slot (area_id, slot_date, window_start, window_end, capacity)
    VALUES (1, CURRENT_DATE + 45, time '08:00', time '10:00', 5)
    RETURNING slot_id INTO s_id;
    SELECT customer_id INTO c1 FROM customer WHERE area_id=1 LIMIT 1;
    SELECT outlet_id  INTO out_id FROM outlet WHERE area_id=1 LIMIT 1;
    INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
    VALUES (c1, s_id, out_id, 'BOOKED', now(), 'T5, Lekki')
    RETURNING order_id INTO o_id;

    BEGIN
        INSERT INTO order_item (order_id, garment_type, quantity, service, unit_price)
        VALUES (o_id, 'shirt', 0, 'wash', 350);
        RAISE EXCEPTION 'FAIL test 5: quantity > 0 NOT enforced';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS test 5: CHECK rejected order_item with quantity = 0';
    END;

    BEGIN
        INSERT INTO order_item (order_id, garment_type, quantity, service, unit_price)
        VALUES (o_id, 'shirt', -1, 'wash', 350);
        RAISE EXCEPTION 'FAIL test 5b: quantity > 0 NOT enforced (negative accepted)';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS test 5b: CHECK rejected order_item with negative quantity';
    END;
END $$;

-- ---- Test 6: payment amount > 0 -----------------------------------
DO $$
DECLARE
    c1 INTEGER; out_id INTEGER; s_id INTEGER; o_id BIGINT;
BEGIN
    INSERT INTO pickup_slot (area_id, slot_date, window_start, window_end, capacity)
    VALUES (1, CURRENT_DATE + 46, time '08:00', time '10:00', 5)
    RETURNING slot_id INTO s_id;
    SELECT customer_id INTO c1 FROM customer WHERE area_id=1 LIMIT 1;
    SELECT outlet_id  INTO out_id FROM outlet WHERE area_id=1 LIMIT 1;
    INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
    VALUES (c1, s_id, out_id, 'BOOKED', now(), 'T6, Lekki')
    RETURNING order_id INTO o_id;

    BEGIN
        INSERT INTO payment (order_id, amount, method, status, reference)
        VALUES (o_id, 0, 'cash', 'paid', 'ZERO-TEST');
        RAISE EXCEPTION 'FAIL test 6: payment amount > 0 NOT enforced';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS test 6: CHECK rejected payment with amount = 0';
    END;

    BEGIN
        INSERT INTO payment (order_id, amount, method, status, reference)
        VALUES (o_id, -500, 'cash', 'paid', 'NEG-TEST');
        RAISE EXCEPTION 'FAIL test 6b: payment amount > 0 NOT enforced (negative accepted)';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS test 6b: CHECK rejected payment with negative amount';
    END;
END $$;

-- ---- Test 7: invalid status transition (BOOKED -> READY directly) ----
DO $$
DECLARE
    c1 INTEGER; out_id INTEGER; s_id INTEGER; o_id BIGINT;
BEGIN
    INSERT INTO pickup_slot (area_id, slot_date, window_start, window_end, capacity)
    VALUES (1, CURRENT_DATE + 47, time '08:00', time '10:00', 5)
    RETURNING slot_id INTO s_id;
    SELECT customer_id INTO c1 FROM customer WHERE area_id=1 LIMIT 1;
    SELECT outlet_id  INTO out_id FROM outlet WHERE area_id=1 LIMIT 1;
    INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
    VALUES (c1, s_id, out_id, 'BOOKED', now(), 'T7, Lekki')
    RETURNING order_id INTO o_id;

    BEGIN
        UPDATE laundry_order SET status = 'READY' WHERE order_id = o_id;
        RAISE EXCEPTION 'FAIL test 7: status transition trigger NOT enforced (BOOKED -> READY accepted)';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS test 7: status transition trigger rejected BOOKED -> READY';
    END;
END $$;

-- ---- Test 8: invalid INITIAL status (INSERT with status='WASHING') --
DO $$
DECLARE
    c1 INTEGER; out_id INTEGER; s_id INTEGER;
BEGIN
    INSERT INTO pickup_slot (area_id, slot_date, window_start, window_end, capacity)
    VALUES (1, CURRENT_DATE + 48, time '08:00', time '10:00', 5)
    RETURNING slot_id INTO s_id;
    SELECT customer_id INTO c1 FROM customer WHERE area_id=1 LIMIT 1;
    SELECT outlet_id  INTO out_id FROM outlet WHERE area_id=1 LIMIT 1;
    BEGIN
        INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
        VALUES (c1, s_id, out_id, 'WASHING', now(), 'T8, Lekki');
        RAISE EXCEPTION 'FAIL test 8: initial status must be BOOKED (WASHING accepted)';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS test 8: trigger rejected INSERT with initial status WASHING';
    END;
END $$;

-- ---- Test 9: CANCELLED is terminal --------------------------------
DO $$
DECLARE
    c1 INTEGER; out_id INTEGER; s_id INTEGER; o_id BIGINT;
BEGIN
    INSERT INTO pickup_slot (area_id, slot_date, window_start, window_end, capacity)
    VALUES (1, CURRENT_DATE + 49, time '08:00', time '10:00', 5)
    RETURNING slot_id INTO s_id;
    SELECT customer_id INTO c1 FROM customer WHERE area_id=1 LIMIT 1;
    SELECT outlet_id  INTO out_id FROM outlet WHERE area_id=1 LIMIT 1;
    INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
    VALUES (c1, s_id, out_id, 'BOOKED', now(), 'T9, Lekki')
    RETURNING order_id INTO o_id;
    UPDATE laundry_order SET status = 'CANCELLED' WHERE order_id = o_id;   -- ok
    BEGIN
        UPDATE laundry_order SET status = 'PICKED_UP' WHERE order_id = o_id;
        RAISE EXCEPTION 'FAIL test 9: CANCELLED is terminal (move to PICKED_UP accepted)';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS test 9: trigger rejected status change out of terminal CANCELLED';
    END;
END $$;

-- ---- Test 10: pickup window must be 2 hours ----------------------
DO $$
BEGIN
    BEGIN
        INSERT INTO pickup_slot (area_id, slot_date, window_start, window_end, capacity)
        VALUES (1, CURRENT_DATE + 50, time '08:00', time '09:00', 5);  -- 1h, not 2h
        RAISE EXCEPTION 'FAIL test 10: 2-hour window NOT enforced';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS test 10: CHECK rejected a slot window that is not 2 hours';
    END;
END $$;

-- ---- Test 11: invalid vehicle ------------------------------------
DO $$
BEGIN
    BEGIN
        INSERT INTO rider (full_name, phone, vehicle, home_area_id, active)
        VALUES ('Bad Rider', '0802 999 9999', 'helicopter', 1, true);
        RAISE EXCEPTION 'FAIL test 11: vehicle CHECK NOT enforced';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS test 11: CHECK rejected invalid vehicle value';
    END;
END $$;

-- ---- Test 12: invalid service ------------------------------------
DO $$
DECLARE
    c1 INTEGER; out_id INTEGER; s_id INTEGER; o_id BIGINT;
BEGIN
    INSERT INTO pickup_slot (area_id, slot_date, window_start, window_end, capacity)
    VALUES (1, CURRENT_DATE + 51, time '08:00', time '10:00', 5)
    RETURNING slot_id INTO s_id;
    SELECT customer_id INTO c1 FROM customer WHERE area_id=1 LIMIT 1;
    SELECT outlet_id  INTO out_id FROM outlet WHERE area_id=1 LIMIT 1;
    INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
    VALUES (c1, s_id, out_id, 'BOOKED', now(), 'T12, Lekki')
    RETURNING order_id INTO o_id;
    BEGIN
        INSERT INTO order_item (order_id, garment_type, quantity, service, unit_price)
        VALUES (o_id, 'shirt', 1, 'starch', 350);   -- invalid service
        RAISE EXCEPTION 'FAIL test 12: service CHECK NOT enforced';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS test 12: CHECK rejected invalid service value';
    END;
END $$;

-- ---- Test 13: only one payment per order (UNIQUE order_id) ---------
DO $$
DECLARE
    c1 INTEGER; out_id INTEGER; s_id INTEGER; o_id BIGINT;
BEGIN
    INSERT INTO pickup_slot (area_id, slot_date, window_start, window_end, capacity)
    VALUES (1, CURRENT_DATE + 52, time '08:00', time '10:00', 5)
    RETURNING slot_id INTO s_id;
    SELECT customer_id INTO c1 FROM customer WHERE area_id=1 LIMIT 1;
    SELECT outlet_id  INTO out_id FROM outlet WHERE area_id=1 LIMIT 1;
    INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
    VALUES (c1, s_id, out_id, 'BOOKED', now(), 'T13, Lekki')
    RETURNING order_id INTO o_id;
    INSERT INTO payment (order_id, amount, method, status, reference)
    VALUES (o_id, 1000, 'cash', 'paid', 'DUP-1');
    BEGIN
        INSERT INTO payment (order_id, amount, method, status, reference)
        VALUES (o_id, 1000, 'cash', 'paid', 'DUP-2');
        RAISE EXCEPTION 'FAIL test 13: UNIQUE(payment.order_id) NOT enforced';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS test 13: UNIQUE rejected a second payment for the same order';
    END;
END $$;

\echo '=========================================================='
\echo ' End of constraint tests (every line above should say PASS)'
\echo '=========================================================='
