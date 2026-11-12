-- =============================================================================
-- 04_seed_data.sql  —  FreshFold Laundry reference + starter data
-- Portfolio 1 · Olla Babafemi · 2026/A/MIT/0111
--
-- Seeds the dimension tables (areas, outlets, customers, riders) and a small
-- starter set of pickup slots for the next 30 days (relative to CURRENT_DATE,
-- so this script never expires). The BULK 50,000+ order generator is
-- 05_bulk_generator.py, which creates its own slots across a 2-year span and
-- fills them up to capacity.
--
-- All names, phone numbers and addresses are realistic Lagos / Nigerian
-- values. Prices are in Nigerian Naira (NGN, ₦).
-- =============================================================================

\set ON_ERROR_STOP on

-- Wipe the fact/helper tables (but keep the schema). Order matters.
TRUNCATE rider_assignment, delivery, payment, order_item, laundry_order
    RESTART IDENTITY CASCADE;
TRUNCATE pickup_slot, rider, customer, outlet, area
    RESTART IDENTITY CASCADE;

-- =============================================================================
-- 1. Areas (Lagos LGAs / neighbourhoods FreshFold operates in)
--    The five required areas: Lekki, Ikeja, Yaba, Surulere, Ajah.
-- =============================================================================
INSERT INTO area (name, lga, region) VALUES
    ('Lekki',     'Eti-Osa',         'Island'),
    ('Ikeja',     'Ikeja',           'Mainland'),
    ('Yaba',      'Lagos Mainland',   'Mainland'),
    ('Surulere',  'Surulere',        'Mainland'),
    ('Ajah',      'Epe',             'Island');

-- =============================================================================
-- 2. Outlets — one per area (5 outlets)
-- =============================================================================
INSERT INTO outlet (name, area_id, address, phone) VALUES
    ('FreshFold Lekki',     1, '12 Admiralty Way, Lekki Phase 1, Eti-Osa',      '0801 111 0001'),
    ('FreshFold Ikeja',     2, '5 Allen Avenue, Ikeja',                          '0801 111 0002'),
    ('FreshFold Yaba',      3, '23 Herbert Macaulay Way, Yaba',                 '0801 111 0003'),
    ('FreshFold Surulere',  4, '8 Adeniran Ogunsanya Street, Surulere',          '0801 111 0004'),
    ('FreshFold Ajah',      5, '40 Abraham Adesanya Street, Ajah',               '0801 111 0005');

-- =============================================================================
-- 3. Customers — 30 realistic Nigerian names across the five areas
-- =============================================================================
INSERT INTO customer (full_name, phone, email, area_id, address) VALUES
    ('Olaide Adebayo',       '0803 220 1011', 'olaide@example.com', 1, 'Block 4, Lekki Phase 1, Eti-Osa'),
    ('Yetunde Okafor',       '0803 220 1012', 'yetunde@example.com',1, '7 Bisi Adewale Street, Lekki'),
    ('Babatunde Williams',   '0803 220 1013', NULL,                 2, '21 Allen Avenue, Ikeja'),
    ('Funke Adeyemi',        '0803 220 1014', 'funke@example.com',  2, '14 Oba Akran Avenue, Ikeja'),
    ('Chinedu Obi',          '0803 220 1015', 'chinedu@example.com',3, '301 Herbert Macaulay Way, Yaba'),
    ('Ngozi Eze',            '0803 220 1016', NULL,                 3, '12 Commercial Avenue, Yaba'),
    ('Emeka Nwosu',          '0803 220 1017', 'emeka@example.com',  4, '5 Adeniran Ogunsanya, Surulere'),
    ('Chioma Okoro',         '0803 220 1018', 'chioma@example.com', 4, '9 Bode Thomas, Surulere'),
    ('Ifeoma Obi',           '0803 220 1019', NULL,                 5, '16 Abraham Adesanya, Ajah'),
    ('Tunde Salami',         '0803 220 1020', 'tunde@example.com',  5, '3 Ajah-Epe Expressway, Ajah'),
    ('Yetunde Bello',        '0803 220 1021', 'yetunde.b@example.com',1, '24 Civic Centre Road, Lekki'),
    ('Kemi Lawal',           '0803 220 1022', 'kemi@example.com',  2, '8 Opebi Link Road, Ikeja'),
    ('Gbenga Olawale',       '0803 220 1023', NULL,                 2, '11 Opebi Road, Ikeja'),
    ('Folake Adeleke',       '0803 220 1024', 'folake@example.com', 3, '14 Sabo Market Road, Yaba'),
    ('Kunle Adekunle',       '0803 220 1025', 'kunle@example.com',  3, '2 Empire Road, Yaba'),
    ('Tope Adesina',         '0803 220 1026', NULL,                 4, '7 Ijesha Road, Surulere'),
    ('Adaeze Eze',           '0803 220 1027', 'adaeze@example.com', 4, '21 Agboola Street, Surulere'),
    ('Seyi Makinde',         '0803 220 1028', 'seyi@example.com',  5, '33 Sangotedo, Ajah'),
    ('Bisi Adewale',         '0803 220 1029', NULL,                 5, '19 Badore Road, Ajah'),
    ('Aisha Bello',          '0803 220 1030', 'aisha@example.com', 1, '5 Oniru Royal Estate, Lekki'),
    ('Ibrahim Musa',         '0803 220 1031', 'ibrahim@example.com',2, '18 Secretariat Road, Ikeja'),
    ('Fatima Abdullahi',     '0803 220 1032', NULL,                 2, '3 Oba Akinjobi Street, Ikeja'),
    ('John Okon',            '0803 220 1033', 'john@example.com',  3, '27 University of Lagos Road, Yaba'),
    ('Mary Effiong',         '0803 220 1034', 'mary@example.com',  3, '10 Alagbon Street, Yaba'),
    ('David Eze',            '0803 220 1035', NULL,                 4, '15 Akangba Street, Surulere'),
    ('Grace Umeh',           '0803 220 1036', 'grace@example.com', 4, '4 Ojuelegba Road, Surulere'),
    ('Samuel Adeniran',      '0803 220 1037', 'samuel@example.com', 5, '8 Idiroko Road, Ajah'),
    ('Patience Okon',        '0803 220 1038', NULL,                 5, '12 Ilaje Road, Ajah'),
    ('Yusuf Ibrahim',        '0803 220 1039', 'yusuf@example.com', 1, '2 Bourdillon Road, Lekki'),
    ('Hauza Suleiman',       '0803 220 1040', 'hauza@example.com', 1, '6 Alexander Road, Lekki');

-- =============================================================================
-- 4. Riders — 12 riders across the five areas, mixed vehicles
-- =============================================================================
INSERT INTO rider (full_name, phone, vehicle, home_area_id, active) VALUES
    ('Adebayo Coker',     '0802 330 2001', 'motorcycle', 1, true),
    ('Idris Lawal',       '0802 330 2002', 'motorcycle', 1, true),
    ('Samuel Oke',        '0802 330 2003', 'tricycle',  2, true),
    ('Kabir Yusuf',       '0802 330 2004', 'motorcycle', 2, true),
    ('Daniel Okafor',     '0802 330 2005', 'motorcycle', 3, true),
    ('Peter Mbah',        '0802 330 2006', 'van',       3, true),
    ('Adewale Johnson',   '0802 330 2007', 'motorcycle', 4, true),
    ('Aminu Bello',       '0802 330 2008', 'tricycle',  4, true),
    ('Chukwuemeka Nnamdi','0802 330 2009', 'motorcycle', 5, true),
    ('Oluwaseun Ade',     '0802 330 2010', 'motorcycle', 5, true),
    ('Hassan Idris',      '0802 330 2011', 'tricycle',  1, true),
    ('Vincent Okorie',    '0802 330 2012', 'van',       2, true);

-- =============================================================================
-- 5. Pickup slots for the next 30 days (relative to CURRENT_DATE).
--    Six 2-hour windows per day: 08-10, 10-12, 12-14, 14-16, 16-18, 18-20.
--    Capacity depends on area (island outlets handle more pickups).
--    This is just a starter set for manual testing + Portfolio 3 demos.
--    The bulk generator creates a full 2-year span of slots itself.
-- =============================================================================
INSERT INTO pickup_slot (area_id, slot_date, window_start, window_end, capacity)
SELECT a.area_id,
       d.day::date,
       w.ws,
       (w.ws + interval '2 hours')::time,
       CASE a.name
           WHEN 'Lekki'    THEN 18
           WHEN 'Ikeja'    THEN 16
           WHEN 'Yaba'     THEN 10
           WHEN 'Surulere' THEN 10
           WHEN 'Ajah'     THEN 8
       END AS capacity
FROM   area a
CROSS JOIN generate_series(CURRENT_DATE, CURRENT_DATE + 29, interval '1 day') AS d(day)
CROSS JOIN (VALUES
              (time '08:00'),
              (time '10:00'),
              (time '12:00'),
              (time '14:00'),
              (time '16:00'),
              (time '18:00')
           ) AS w(ws)
ON CONFLICT (area_id, slot_date, window_start) DO NOTHING;

-- =============================================================================
-- Quick reference price list (Naira, ₦) per (garment_type, service).
-- Used by both the seed and the bulk generator. Stored here as a comment for
-- documentation; the bulk generator hard-codes the same matrix.
--   shirt      wash 350   wash_iron 600   dry_clean 1200
--   trouser    wash 400   wash_iron 700   dry_clean 1400
--   agbada     wash 800   wash_iron 1500  dry_clean 2500
--   iro        wash 700   wash_iron 1300  dry_clean 2200
--   buba       wash 600   wash_iron 1100  dry_clean 2000
--   duvet      wash 2000  wash_iron 3500  dry_clean 5000
--   bedsheet   wash 1200  wash_iron 2200  dry_clean 3500
--   suit       wash 1500  wash_iron 2500  dry_clean 6000
--   blouse     wash 350   wash_iron 600   dry_clean 1200
--   skirt      wash 350   wash_iron 600   dry_clean 1200
-- =============================================================================

\echo 'Seed data loaded: 5 areas, 5 outlets, 30 customers, 12 riders, '
\echo 'and ~900 pickup slots across the next 30 days.'
SELECT 'areas='   || count(*) FROM area;
SELECT 'outlets=' || count(*) FROM outlet;
SELECT 'customers=' || count(*) FROM customer;
SELECT 'riders='  || count(*) FROM rider;
SELECT 'slots='   || count(*) FROM pickup_slot;
