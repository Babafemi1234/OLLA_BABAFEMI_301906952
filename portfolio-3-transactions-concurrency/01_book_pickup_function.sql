-- =============================================================================
-- 01_book_pickup_function.sql  —  Portfolio 3 transactions
-- Portfolio 3 · MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111
-- Case study: FreshFold Laundry (Lagos)
--
-- This file defines the booking transaction in two forms:
--
--   1. book_pickup_naive(...)  — checks slot space with a plain SELECT (NO lock).
--      This is the version the race-condition guide uses to demonstrate the BUG
--      (two concurrent sessions both read "4/5", both insert, slot ends 6/5).
--
--   2. book_pickup(...)        — the production version: takes a SELECT ...
--      FOR UPDATE row lock on the pickup_slot BEFORE counting. This is FIX 1
--      in the race-condition guide. The second session's FOR UPDATE blocks
--      until the first commits, then it re-counts and sees "5/5 = full".
--
-- Both functions:
--   * check the slot has space,
--   * create the laundry_order (status BOOKED),
--   * insert the order_items from a JSONB array,
--   * insert the payment (status 'paid'),
--   * raise PAYMENT_FAILED if p_simulate_payment_failure is true, which
--     rolls back the whole transaction (so the order does NOT persist).
--
-- The SERIALIZABLE retry (FIX 2 in the race guide) is NOT a function here,
-- because a SERIALIZABLE retry must run in a NEW transaction (a new snapshot),
-- which a PL/pgSQL function cannot start. The guide therefore demonstrates
-- FIX 2 with raw SQL in two psql sessions and a manual retry, exactly as a
-- client library (psycopg2 / JDBC) would do automatically.
-- =============================================================================

\set ON_ERROR_STOP on

-- Drop previous versions if any
DROP FUNCTION IF EXISTS book_pickup_naive(int, int, jsonb, text, numeric, boolean);
DROP FUNCTION IF EXISTS book_pickup     (int, int, jsonb, text, numeric, boolean);

-- =============================================================================
-- 1. NAIVE version — the BUG. No row lock before the capacity check.
-- =============================================================================
CREATE OR REPLACE FUNCTION book_pickup_naive(
    p_customer_id               INTEGER,
    p_slot_id                   INTEGER,
    p_items                     JSONB,        -- [{"garment_type":"shirt","quantity":2,"service":"wash_iron","unit_price":600}, ...]
    p_method                    TEXT,
    p_amount                    NUMERIC,
    p_simulate_payment_failure  BOOLEAN DEFAULT FALSE
) RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id   BIGINT;
    v_outlet_id  INTEGER;
    v_capacity   INTEGER;
    v_used       INTEGER;
    v_item       JSONB;
    v_reference TEXT;
BEGIN
    -- (1) Read the slot capacity + outlet WITHOUT locking the row.
    SELECT s.capacity, o.outlet_id
      INTO v_capacity, v_outlet_id
      FROM pickup_slot s
      JOIN area a ON a.area_id = s.area_id
      JOIN outlet o ON o.area_id = a.area_id    -- the outlet in the slot's area
     WHERE s.slot_id = p_slot_id
     LIMIT 1;

    IF v_capacity IS NULL THEN
        RAISE EXCEPTION 'Slot % does not exist', p_slot_id;
    END IF;

    -- (2) Count active orders for this slot (NO lock -> the race window).
    SELECT count(*) INTO v_used
      FROM laundry_order
     WHERE slot_id = p_slot_id
       AND status <> 'CANCELLED';

    IF v_used >= v_capacity THEN
        RAISE EXCEPTION 'Slot % is full (% / %)', p_slot_id, v_used, v_capacity;
    END IF;

    -- (3) Create the order (status BOOKED; the capacity trigger double-checks).
    INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status,
                               booked_at, delivery_address)
    VALUES (p_customer_id, p_slot_id, v_outlet_id, 'BOOKED', now(),
            'Customer address, Lagos')
    RETURNING order_id INTO v_order_id;

    -- (4) Insert the order items from the JSONB array.
    FOR v_item IN SELECT jsonb_array_elements(p_items) LOOP
        INSERT INTO order_item (order_id, garment_type, quantity, service, unit_price)
        VALUES (v_order_id,
                v_item->>'garment_type',
                (v_item->>'quantity')::INTEGER,
                v_item->>'service',
                (v_item->>'unit_price')::NUMERIC);
    END LOOP;

    -- (5) Record the payment. Simulate a gateway failure if requested.
    IF p_simulate_payment_failure THEN
        -- Simulate a payment-gateway decline: raise BEFORE the payment row
        -- exists, so the whole transaction (order + items) is rolled back.
        RAISE EXCEPTION 'PAYMENT_FAILED: payment gateway declined the card'
            USING ERRCODE = '40001';
    END IF;

    v_reference := 'FF-BOOK-' || v_order_id;
    INSERT INTO payment (order_id, amount, method, status, reference, paid_at)
    VALUES (v_order_id, p_amount, p_method, 'paid', v_reference, now());

    RETURN v_order_id;
END;
$$;

-- =============================================================================
-- 2. SAFE version (FIX 1) — SELECT ... FOR UPDATE on the slot row.
--    The second concurrent caller's FOR UPDATE blocks until the first commits
--    (or rolls back); then it re-reads the row and re-counts, so it sees the
--    new count and rejects an over-capacity booking.
-- =============================================================================
CREATE OR REPLACE FUNCTION book_pickup(
    p_customer_id               INTEGER,
    p_slot_id                   INTEGER,
    p_items                     JSONB,
    p_method                    TEXT,
    p_amount                    NUMERIC,
    p_simulate_payment_failure  BOOLEAN DEFAULT FALSE
) RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_slot       pickup_slot%ROWTYPE;
    v_order_id   BIGINT;
    v_outlet_id  INTEGER;
    v_used       INTEGER;
    v_item       JSONB;
    v_reference  TEXT;
BEGIN
    -- (1) Lock the slot row. Other callers' FOR UPDATE will BLOCK here until
    --     this transaction commits or rolls back. This is FIX 1.
    SELECT * INTO v_slot
      FROM pickup_slot
     WHERE slot_id = p_slot_id
     FOR UPDATE;                          -- <--- the key line

    IF v_slot.slot_id IS NULL THEN
        RAISE EXCEPTION 'Slot % does not exist', p_slot_id;
    END IF;

    -- Outlet in the slot's area (so the order is fulfilled by the local branch).
    SELECT o.outlet_id INTO v_outlet_id
      FROM outlet o
     WHERE o.area_id = v_slot.area_id
     LIMIT 1;

    -- (2) Re-count AFTER acquiring the lock. Any concurrent booking that
    --     committed while we waited is now visible, so v_used is fresh.
    SELECT count(*) INTO v_used
      FROM laundry_order
     WHERE slot_id = p_slot_id
       AND status <> 'CANCELLED';

    IF v_used >= v_slot.capacity THEN
        RAISE EXCEPTION 'Slot % is full (% / %). Booking rejected.',
            p_slot_id, v_used, v_slot.capacity
            USING ERRCODE = '40001';
    END IF;

    -- (3) Create the order.
    INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status,
                               booked_at, delivery_address)
    VALUES (p_customer_id, p_slot_id, v_outlet_id, 'BOOKED', now(),
            'Customer address, Lagos')
    RETURNING order_id INTO v_order_id;

    -- (4) Items.
    FOR v_item IN SELECT jsonb_array_elements(p_items) LOOP
        INSERT INTO order_item (order_id, garment_type, quantity, service, unit_price)
        VALUES (v_order_id,
                v_item->>'garment_type',
                (v_item->>'quantity')::INTEGER,
                v_item->>'service',
                (v_item->>'unit_price')::NUMERIC);
    END LOOP;

    -- (5) Payment, with optional simulated failure.
    IF p_simulate_payment_failure THEN
        RAISE EXCEPTION 'PAYMENT_FAILED: payment gateway declined the card'
            USING ERRCODE = '40001';
    END IF;
    v_reference := 'FF-BOOK-' || v_order_id;
    INSERT INTO payment (order_id, amount, method, status, reference, paid_at)
    VALUES (v_order_id, p_amount, p_method, 'paid', v_reference, now());

    RETURN v_order_id;
END;
$$;

\echo 'book_pickup_naive() and book_pickup() defined.'
