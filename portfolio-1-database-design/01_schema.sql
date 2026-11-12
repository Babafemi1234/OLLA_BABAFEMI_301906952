-- =============================================================================
-- 01_schema.sql  —  FreshFold Laundry  (Portfolio 1: Database Design)
-- Course : MIT 8103 Advanced Database Systems, Miva Open University
-- Student: Olla Babafemi  |  2026/A/MIT/0111
-- Target : PostgreSQL 16  (run via the Unix socket — see run_p1.sh)
--
-- This file creates the WHOLE relational schema for the FreshFold Laundry case
-- study: 9 core entities (area, outlet, customer, rider, pickup_slot,
-- laundry_order, order_item, payment, delivery) plus one helper entity
-- (rider_assignment) that lets us enforce "a rider can't be assigned two
-- overlapping pickups OR deliveries" with a single EXCLUDE constraint using
-- btree_gist on a tstzrange.
--
-- Constraints implemented here
--   * Primary keys, foreign keys, UNIQUE, CHECK (quantity > 0, amount > 0,
--     2-hour pickup window, delivery time after pickup time, valid status).
--   * Trigger 1  enforce_slot_capacity        — a slot may not accept more
--     orders than its capacity (naive row-level guard; the concurrency hole is
--     the subject of Portfolio 3).
--   * Trigger 2  enforce_status_transition    — order status must follow
--     BOOKED → PICKED_UP → WASHING → READY → DELIVERED, or branch to CANCELLED.
--   * Trigger 3  sync_pickup_assignment       — keeps rider_assignment in
--     sync with laundry_order.pickup_rider_id and the slot window.
--   * Trigger 4  sync_delivery_assignment     — keeps rider_assignment in
--     sync with delivery.rider_id and [picked_up_at, delivered_at].
--   * EXCLUDE constraint on rider_assignment (btree_gist, tstzrange &&) — a
--     rider cannot hold two overlapping assignments of any kind.
--
-- All dates use timestamptz / date and are relative to CURRENT_DATE in the
-- seed + bulk generator, so the data never expires.
-- =============================================================================

\set ON_ERROR_STOP on

-- Drop in dependency-safe order so the script is fully idempotent.
DROP TABLE IF EXISTS rider_assignment CASCADE;
DROP TABLE IF EXISTS delivery        CASCADE;
DROP TABLE IF EXISTS payment          CASCADE;
DROP TABLE IF EXISTS order_item       CASCADE;
DROP TABLE IF EXISTS laundry_order    CASCADE;
DROP TABLE IF EXISTS pickup_slot      CASCADE;
DROP TABLE IF EXISTS rider            CASCADE;
DROP TABLE IF EXISTS customer         CASCADE;
DROP TABLE IF EXISTS outlet           CASCADE;
DROP TABLE IF EXISTS area             CASCADE;

-- Extensions
CREATE EXTENSION IF NOT EXISTS btree_gist;   -- needed for EXCLUDE on (rider_id =, range &&)
CREATE EXTENSION IF NOT EXISTS pg_trgm;       -- optional, for name LIKE searches in P2

-- =============================================================================
-- 1. area  (LGA — Local Government Area, the Lagos sub-region we operate in)
-- =============================================================================
CREATE TABLE area (
    area_id    SERIAL PRIMARY KEY,
    name       TEXT NOT NULL,                       -- e.g. 'Eti-Osa (Lekki)'
    lga        TEXT NOT NULL,                       -- e.g. 'Eti-Osa'
    region     TEXT NOT NULL CHECK (region IN ('Island','Mainland')),
    created_at timestamptz NOT NULL DEFAULT now()
);
-- A named LGA should appear once.
CREATE UNIQUE INDEX uq_area_lga ON area (lga);

-- =============================================================================
-- 2. outlet  (a FreshFold physical laundry branch, sits inside one area)
-- =============================================================================
CREATE TABLE outlet (
    outlet_id  SERIAL PRIMARY KEY,
    name       TEXT NOT NULL,
    area_id    INTEGER NOT NULL REFERENCES area(area_id),
    address    TEXT NOT NULL,
    phone      TEXT NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- 3. customer
-- =============================================================================
CREATE TABLE customer (
    customer_id SERIAL PRIMARY KEY,
    full_name   TEXT NOT NULL,
    phone       TEXT NOT NULL,
    email       TEXT,
    area_id     INTEGER NOT NULL REFERENCES area(area_id),
    address     TEXT NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_customer_area ON customer (area_id);

-- =============================================================================
-- 4. rider
-- =============================================================================
CREATE TABLE rider (
    rider_id     SERIAL PRIMARY KEY,
    full_name    TEXT NOT NULL,
    phone        TEXT NOT NULL,
    vehicle      TEXT NOT NULL CHECK (vehicle IN ('motorcycle','tricycle','van')),
    home_area_id INTEGER NOT NULL REFERENCES area(area_id),
    active       BOOLEAN NOT NULL DEFAULT true,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_rider_active ON rider (active);

-- =============================================================================
-- 5. pickup_slot  (area + date + 2-hour window + capacity)
-- =============================================================================
CREATE TABLE pickup_slot (
    slot_id      SERIAL PRIMARY KEY,
    area_id      INTEGER NOT NULL REFERENCES area(area_id),
    slot_date    DATE    NOT NULL,
    window_start TIME    NOT NULL,
    window_end   TIME    NOT NULL,
    capacity     INTEGER NOT NULL CHECK (capacity > 0),
    created_at   timestamptz NOT NULL DEFAULT now(),
    -- One slot per (area, date, window_start).
    CONSTRAINT uq_slot UNIQUE (area_id, slot_date, window_start),
    -- Enforce a 2-hour window.
    CONSTRAINT chk_slot_two_hour_window
        CHECK (window_end = (window_start + interval '2 hours')::time)
    -- Note: we deliberately do NOT require slot_date to be in the future. The
    -- bulk generator (05_bulk_generator.py) creates 2 years of historical slots
    -- so that revenue/turnaround queries have data, and the seed creates
    -- slots for the next 30 days. All dates are relative to CURRENT_DATE.
);
CREATE INDEX idx_slot_lookup ON pickup_slot (area_id, slot_date, window_start);

-- =============================================================================
-- 6. laundry_order  (the central fact table)
-- =============================================================================
CREATE TABLE laundry_order (
    order_id          BIGSERIAL PRIMARY KEY,
    customer_id       INTEGER NOT NULL REFERENCES customer(customer_id),
    slot_id           INTEGER NOT NULL REFERENCES pickup_slot(slot_id),
    outlet_id         INTEGER NOT NULL REFERENCES outlet(outlet_id),
    pickup_rider_id   INTEGER REFERENCES rider(rider_id),
    delivery_rider_id INTEGER REFERENCES rider(rider_id),
    status            TEXT NOT NULL DEFAULT 'BOOKED'
                        CHECK (status IN
                          ('BOOKED','PICKED_UP','WASHING','READY','DELIVERED','CANCELLED')),
    booked_at         timestamptz NOT NULL DEFAULT now(),
    picked_up_at      timestamptz,
    washing_started_at timestamptz,
    ready_at          timestamptz,
    delivered_at      timestamptz,
    delivery_address  TEXT NOT NULL,
    created_at        timestamptz NOT NULL DEFAULT now(),
    -- delivery time must be after pickup time (when both are known)
    CONSTRAINT chk_delivery_after_pickup
        CHECK (delivered_at IS NULL OR picked_up_at IS NULL OR delivered_at > picked_up_at),
    -- the workflow timestamps must be monotonic
    CONSTRAINT chk_washing_after_pickup
        CHECK (washing_started_at IS NULL OR picked_up_at IS NULL OR washing_started_at >= picked_up_at),
    CONSTRAINT chk_ready_after_washing
        CHECK (ready_at IS NULL OR washing_started_at IS NULL OR ready_at >= washing_started_at),
    CONSTRAINT chk_delivered_after_ready
        CHECK (delivered_at IS NULL OR ready_at IS NULL OR delivered_at >= ready_at)
);
CREATE INDEX idx_order_slot    ON laundry_order (slot_id);
CREATE INDEX idx_order_outlet  ON laundry_order (outlet_id);
CREATE INDEX idx_order_status ON laundry_order (status);
CREATE INDEX idx_order_booked ON laundry_order (booked_at);

-- =============================================================================
-- 7. order_item  (garment type, quantity, service)
-- =============================================================================
CREATE TABLE order_item (
    item_id      BIGSERIAL PRIMARY KEY,
    order_id     BIGINT NOT NULL REFERENCES laundry_order(order_id) ON DELETE CASCADE,
    garment_type TEXT   NOT NULL,
    quantity     INTEGER NOT NULL CHECK (quantity > 0),
    service      TEXT   NOT NULL CHECK (service IN ('wash','wash_iron','dry_clean')),
    unit_price   NUMERIC(12,2) NOT NULL CHECK (unit_price > 0),    -- in Naira (₦)
    line_total   NUMERIC(12,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_item_order   ON order_item (order_id);
CREATE INDEX idx_item_garment ON order_item (garment_type);

-- =============================================================================
-- 8. payment  (one per order)
-- =============================================================================
CREATE TABLE payment (
    payment_id  BIGSERIAL PRIMARY KEY,
    order_id    BIGINT NOT NULL UNIQUE REFERENCES laundry_order(order_id) ON DELETE CASCADE,
    amount      NUMERIC(12,2) NOT NULL CHECK (amount > 0),          -- in Naira
    method      TEXT NOT NULL CHECK (method IN ('card','transfer','cash','ussd')),
    status      TEXT NOT NULL DEFAULT 'paid'
                  CHECK (status IN ('paid','failed','refunded')),
    reference   TEXT UNIQUE,
    paid_at     timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_payment_status ON payment (status);

-- =============================================================================
-- 9. delivery  (one per order; records the rider who delivered and the times)
-- =============================================================================
CREATE TABLE delivery (
    delivery_id   BIGSERIAL PRIMARY KEY,
    order_id       BIGINT NOT NULL UNIQUE REFERENCES laundry_order(order_id) ON DELETE CASCADE,
    rider_id       INTEGER NOT NULL REFERENCES rider(rider_id),
    picked_up_at   timestamptz NOT NULL,
    delivered_at   timestamptz NOT NULL,
    signature      TEXT,                          -- recipient name / signature
    created_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_delivery_window_positive
        CHECK (delivered_at > picked_up_at)
);
CREATE INDEX idx_delivery_rider ON delivery (rider_id);

-- =============================================================================
-- 10. rider_assignment  (HELPER for the unified exclusion constraint)
--     One row per (rider, order, kind) with a tstzrange busy_range. The EXCLUDE
--     constraint below is the single source of truth for "a rider can't be
--     assigned two overlapping pickups OR deliveries".
-- =============================================================================
CREATE TABLE rider_assignment (
    assignment_id BIGSERIAL PRIMARY KEY,
    rider_id      INTEGER NOT NULL REFERENCES rider(rider_id) ON DELETE CASCADE,
    order_id      BIGINT  NOT NULL REFERENCES laundry_order(order_id) ON DELETE CASCADE,
    kind          TEXT NOT NULL CHECK (kind IN ('pickup','delivery')),
    busy_range    tstzrange NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    -- One assignment per (order, kind): an order has at most one pickup
    -- assignment and at most one delivery assignment.
    CONSTRAINT uq_assignment_order_kind UNIQUE (order_id, kind),
    -- The exclusion constraint. btree_gist supplies the gist operator class
    -- for the scalar rider_id so it can be combined with the tstzrange && test
    -- in one EXCLUDE. This forbids any two overlapping assignments for the
    -- same rider, regardless of whether they are pickups or deliveries.
    CONSTRAINT excl_rider_no_overlap
        EXCLUDE USING gist (rider_id WITH =, busy_range WITH &&)
);
CREATE INDEX idx_assignment_rider ON rider_assignment (rider_id);

-- =============================================================================
-- TRIGGER FUNCTIONS
-- =============================================================================

-- ---- Trigger 1: enforce_slot_capacity -------------------------------
-- Naive row-level capacity guard. Rejects an INSERT/UPDATE that would push a
-- slot past its capacity by counting existing orders for that slot at the
-- moment of the statement. This guard is correct for single-statement work
-- but is NOT safe under concurrent transactions — that race condition is
-- exactly what Portfolio 3 demonstrates and fixes (SELECT FOR UPDATE and
-- SERIALIZABLE + retry).
CREATE OR REPLACE FUNCTION enforce_slot_capacity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    current_count INTEGER;
    slot_cap      INTEGER;
BEGIN
    SELECT capacity INTO slot_cap
      FROM pickup_slot
     WHERE slot_id = NEW.slot_id;

    SELECT count(*) INTO current_count
      FROM laundry_order
     WHERE slot_id = NEW.slot_id
       AND status <> 'CANCELLED';

    IF current_count >= slot_cap THEN
        RAISE EXCEPTION
            'Slot % is full (% / %). Booking rejected.',
            NEW.slot_id, current_count, slot_cap
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_slot_capacity ON laundry_order;
CREATE TRIGGER trg_slot_capacity
    BEFORE INSERT OR UPDATE OF slot_id ON laundry_order
    FOR EACH ROW EXECUTE FUNCTION enforce_slot_capacity();

-- ---- Trigger 2: enforce_status_transition ---------------------------
-- Order status must follow the valid lifecycle:
--   BOOKED → PICKED_UP → WASHING → READY → DELIVERED
--   BOOKED → CANCELLED  (cancellation only allowed before pickup)
-- CANCELLED and DELIVERED are terminal.
CREATE OR REPLACE FUNCTION enforce_status_transition()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- INSERT (TG_OP = 'INSERT'): NEW.status must be BOOKED (or CANCELLED).
    IF TG_OP = 'INSERT' THEN
        IF NEW.status NOT IN ('BOOKED','CANCELLED') THEN
            RAISE EXCEPTION 'Initial order status must be BOOKED (got %).',
                NEW.status USING ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
    END IF;

    -- UPDATE: enforce the transition matrix.
    IF NEW.status = OLD.status THEN
        RETURN NEW;  -- no change, nothing to check
    END IF;

    IF OLD.status = 'CANCELLED' THEN
        RAISE EXCEPTION 'Order % is CANCELLED (terminal). Cannot move to %.',
            OLD.order_id, NEW.status USING ERRCODE = 'check_violation';
    END IF;

    IF OLD.status = 'DELIVERED' THEN
        RAISE EXCEPTION 'Order % is DELIVERED (terminal). Cannot move to %.',
            OLD.order_id, NEW.status USING ERRCODE = 'check_violation';
    END IF;

    CASE
        WHEN OLD.status = 'BOOKED'    AND NEW.status IN ('PICKED_UP','CANCELLED') THEN NULL;
        WHEN OLD.status = 'PICKED_UP' AND NEW.status = 'WASHING'  THEN NULL;
        WHEN OLD.status = 'WASHING'   AND NEW.status = 'READY'     THEN NULL;
        WHEN OLD.status = 'READY'     AND NEW.status = 'DELIVERED' THEN NULL;
        ELSE RAISE EXCEPTION
            'Invalid status transition for order %: % -> %.',
            OLD.order_id, OLD.status, NEW.status
            USING ERRCODE = 'check_violation';
    END CASE;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_status_transition ON laundry_order;
CREATE TRIGGER trg_status_transition
    BEFORE INSERT OR UPDATE OF status ON laundry_order
    FOR EACH ROW EXECUTE FUNCTION enforce_status_transition();

-- ---- Trigger 3: sync_pickup_assignment ------------------------------
-- Whenever an order gets (or changes) its pickup_rider_id, keep the matching
-- rider_assignment row in sync. The busy range is the slot's 2-hour window
-- (slot_date + window_start .. slot_date + window_end).
CREATE OR REPLACE FUNCTION sync_pickup_assignment()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    win_start_ts timestamptz;
    win_end_ts   timestamptz;
BEGIN
    -- Always delete the old pickup assignment for this order first.
    DELETE FROM rider_assignment WHERE order_id = NEW.order_id AND kind = 'pickup';

    IF NEW.pickup_rider_id IS NOT NULL THEN
        -- Interpret the slot's wall-clock window as Lagos (Africa/Lagos) time
        -- and convert to absolute timestamptz so the EXCLUDE constraint on
        -- tstzrange compares apples to apples.
        SELECT (pickup_slot.slot_date + pickup_slot.window_start) AT TIME ZONE 'Africa/Lagos',
               (pickup_slot.slot_date + pickup_slot.window_end)   AT TIME ZONE 'Africa/Lagos'
          INTO win_start_ts, win_end_ts
          FROM pickup_slot
         WHERE pickup_slot.slot_id = NEW.slot_id;

        INSERT INTO rider_assignment (rider_id, order_id, kind, busy_range)
        VALUES (NEW.pickup_rider_id, NEW.order_id, 'pickup',
                tstzrange(win_start_ts, win_end_ts, '[)'));
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_pickup_assignment ON laundry_order;
CREATE TRIGGER trg_sync_pickup_assignment
    AFTER INSERT OR UPDATE OF pickup_rider_id ON laundry_order
    FOR EACH ROW EXECUTE FUNCTION sync_pickup_assignment();

-- ---- Trigger 4: sync_delivery_assignment ----------------------------
-- Whenever a delivery row is created or its rider changes, keep the matching
-- rider_assignment row in sync. The busy range is [picked_up_at, delivered_at].
CREATE OR REPLACE FUNCTION sync_delivery_assignment()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM rider_assignment WHERE order_id = NEW.order_id AND kind = 'delivery';

    INSERT INTO rider_assignment (rider_id, order_id, kind, busy_range)
    VALUES (NEW.rider_id, NEW.order_id, 'delivery',
            tstzrange(NEW.picked_up_at, NEW.delivered_at, '[)'));
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_delivery_assignment ON delivery;
CREATE TRIGGER trg_sync_delivery_assignment
    AFTER INSERT OR UPDATE OF rider_id, picked_up_at, delivered_at ON delivery
    FOR EACH ROW EXECUTE FUNCTION sync_delivery_assignment();

-- =============================================================================
-- Helpful views (used by P2 queries; defined here so the schema is self-contained)
-- =============================================================================
CREATE OR REPLACE VIEW v_order_revenue AS
SELECT o.order_id,
       o.outlet_id,
       c.area_id        AS customer_area_id,
       o.booked_at,
       o.status,
       COALESCE(SUM(i.line_total), 0)            AS order_value,
       COALESCE(p.amount, 0)                      AS paid_amount,
       p.status                                   AS payment_status
FROM laundry_order o
JOIN customer c       ON c.customer_id = o.customer_id
LEFT JOIN order_item i ON i.order_id = o.order_id
LEFT JOIN payment p    ON p.order_id   = o.order_id
GROUP BY o.order_id, c.area_id, o.outlet_id, o.booked_at, o.status, p.amount, p.status;

-- Done.
\echo 'Schema created successfully.'
