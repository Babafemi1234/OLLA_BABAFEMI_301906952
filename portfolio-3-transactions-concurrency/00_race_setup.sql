-- =============================================================================
-- 00_race_setup.sql  —  Portfolio 3 race-condition fixture
-- Portfolio 3 · MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111
--
-- Creates a pickup slot with capacity 5 and puts EXACTLY 4 non-cancelled orders
-- into it, so the slot sits at 4/5. This is the starting state for the
-- two-terminal race-condition guide (03_race_condition_guide.md).
--
-- Idempotent: re-running it resets the slot back to exactly 4/5.
--
-- Run with:  psql -h /var/run/postgresql -U freshfold -d freshfold -f 00_race_setup.sql
-- =============================================================================

\set ON_ERROR_STOP on

-- The race slot: area 1 (Lekki), capacity 5, on a date that is unambiguously
-- in the future relative to today.
INSERT INTO pickup_slot (area_id, slot_date, window_start, window_end, capacity)
VALUES (1, CURRENT_DATE + 21, time '10:00', time '12:00', 5)
ON CONFLICT (area_id, slot_date, window_start) DO UPDATE SET capacity = EXCLUDED.capacity;

SELECT slot_id AS race_slot_id
  FROM pickup_slot
 WHERE area_id=1 AND slot_date=CURRENT_DATE+21 AND window_start=time '10:00'
 \gset

-- Reset the slot: delete everything currently in it (orders, items, payments,
-- deliveries cascade). Then put exactly 4 fresh BOOKED orders in.
DELETE FROM laundry_order WHERE slot_id = :race_slot_id;

-- Need 4 distinct customers in area 1 (create spares if there are fewer than 4).
INSERT INTO customer (full_name, phone, email, area_id, address)
SELECT c.fn, c.phone, c.email, 1, c.addr
FROM (VALUES
    ('Race Cust 1', '0809 555 0001', 'race1@example.com', '1 Race Rd, Lekki'),
    ('Race Cust 2', '0809 555 0002', 'race2@example.com', '2 Race Rd, Lekki'),
    ('Race Cust 3', '0809 555 0003', 'race3@example.com', '3 Race Rd, Lekki'),
    ('Race Cust 4', '0809 555 0004', 'race4@example.com', '4 Race Rd, Lekki')
) AS c(fn, phone, email, addr)
WHERE NOT EXISTS (SELECT 1 FROM customer x WHERE x.email = c.email);

-- 4 existing bookings (committed) so the slot is at 4/5.
INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
SELECT c.customer_id, :race_slot_id,
       (SELECT min(o.outlet_id) FROM outlet o WHERE o.area_id = 1),
       'BOOKED', now(), c.address
FROM customer c
WHERE c.email IN ('race1@example.com','race2@example.com',
                  'race3@example.com','race4@example.com');

-- A small paid payment for each (so they look like real bookings).
INSERT INTO payment (order_id, amount, method, status, reference, paid_at)
SELECT l.order_id, 1000, 'cash', 'paid', 'FF-RACE-'||l.order_id, now()
FROM laundry_order l
WHERE l.slot_id = :race_slot_id
  AND NOT EXISTS (SELECT 1 FROM payment p WHERE p.order_id = l.order_id);

-- Report the starting state.
\echo '===================================================='
\echo ' Race fixture ready.'
\echo '===================================================='
SELECT s.slot_id, s.capacity,
       count(l.order_id) AS used,
       s.capacity - count(l.order_id) AS free_spaces
FROM   pickup_slot s
LEFT JOIN laundry_order l
       ON l.slot_id = s.slot_id AND l.status <> 'CANCELLED'
WHERE  s.slot_id = :race_slot_id
GROUP BY s.slot_id, s.capacity;
\echo '  The slot should now show capacity=5, used=4, free_spaces=1.'
\echo '  Open TWO psql sessions to demonstrate the race (see'
\echo '  03_race_condition_guide.md).'
\echo '===================================================='
