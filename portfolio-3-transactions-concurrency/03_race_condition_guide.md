# Portfolio 3 — The "last space in a pickup slot" race condition (two-terminal guide)

**Student:** Olla Babafemi · **Matric:** 2026/A/MIT/0111 · **Course:** MIT 8103 Advanced Database Systems
**Case study:** FreshFold Laundry (Lagos) · **Study sessions covered:** Study Session 1 (ACID foundations) + Study Session 2 (consistency models, CAP / ACID trade-offs).

This document is a **step-by-step guide for two interactive `psql` sessions** running
side by side. It demonstrates the over-booking race condition on the **last free
space** in a pickup slot, then shows the two production fixes:

1. **FIX 1 — `SELECT ... FOR UPDATE` on the slot row.** The second session blocks
   until the first commits, then re-counts and sees the slot is full.
2. **FIX 2 — `SERIALIZABLE` isolation level with a retry.** The second session's
   `COMMIT` fails with `serialization_failure` (SQLSTATE `40001`); the client
   retries in a fresh transaction, re-counts, and sees the slot is full.

> **Honesty rule.** Every `[paste real output here]` slot is for YOUR captured
> output. Do not invent timings, counts, or error messages. Run the commands
> in two real `psql` windows and paste what you actually see.

---

## Step 0 — prepare the fixture (run once, in any terminal)

```bash
cd advanced-database-portfolio/portfolio-3-transactions-concurrency
psql -h /var/run/postgresql -U freshfold -d freshfold -f 00_race_setup.sql
```

Expected output:
```
[paste real output here — should show capacity=5, used=4, free_spaces=1]
```

Then open **two** separate `psql` sessions (Terminal A and Terminal B):

```bash
# Terminal A
psql -h /var/run/postgresql -U freshfold -d freshfold

# Terminal B  (a second window)
psql -h /var/run/postgresql -U freshfold -d freshfold
```

Find the race slot id once (run in either terminal, copy the number):

```sql
SELECT slot_id FROM pickup_slot
 WHERE area_id=1 AND slot_date=CURRENT_DATE+21 AND window_start=time '10:00';
```

```
[paste real output here — note the slot_id, call it RACE_SLOT below]
```

In the steps below, replace `RACE_SLOT` with that number.

---

## Part 1 — THE BUG (the naive check races and the slot overbooks)

The naive capacity check does a plain `SELECT count(*)` (no lock) and then
`INSERT`. Under the default **READ COMMITTED** isolation level, each
transaction's count only sees *committed* rows — the other transaction's
uncommitted insert is invisible — so both sessions read "4/5", both insert, and
the slot ends up at **6/5**.

> The capacity trigger from Portfolio 1 (`enforce_slot_capacity`) is the same
> naive check, so it also fails to prevent this race. The trigger is a
> *single-statement* guard, not a *cross-transaction* lock.

Run these commands **in order, alternating between the two terminals**:

### Step 1.1 — both sessions BEGIN and count

**Terminal A:**
```sql
BEGIN;
SELECT count(*) AS a_count FROM laundry_order
 WHERE slot_id = RACE_SLOT AND status <> 'CANCELLED';
```
```
[paste real output here — expect a_count = 4]
```

**Terminal B:**
```sql
BEGIN;
SELECT count(*) AS b_count FROM laundry_order
 WHERE slot_id = RACE_SLOT AND status <> 'CANCELLED';
```
```
[paste real output here — expect b_count = 4]
```

Both sessions now believe there is 1 free space.

### Step 1.2 — both sessions INSERT the "last" order

**Terminal A:**
```sql
INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
SELECT (SELECT customer_id FROM customer WHERE email='race1@example.com'),
       RACE_SLOT,
       (SELECT outlet_id FROM outlet WHERE area_id=1 LIMIT 1),
       'BOOKED', now(), '1 Race Rd, Lekki';
```
```
[paste real output here — expect INSERT 0 1]
```

**Terminal B:**
```sql
INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
SELECT (SELECT customer_id FROM customer WHERE email='race2@example.com'),
       RACE_SLOT,
       (SELECT outlet_id FROM outlet WHERE area_id=1 LIMIT 1),
       'BOOKED', now(), '2 Race Rd, Lekki';
```
```
[paste real output here — expect INSERT 0 1  (the bug: B's trigger count only sees committed rows = 4, so 4 < 5 passes)]
```

### Step 1.3 — both sessions COMMIT

**Terminal A:**
```sql
COMMIT;
```
```
[paste real output here]
```

**Terminal B:**
```sql
COMMIT;
```
```
[paste real output here]
```

### Step 1.4 — observe the overbooked slot (in either terminal)

```sql
SELECT s.capacity, count(l.order_id) AS used, s.capacity - count(l.order_id) AS free_spaces
FROM   pickup_slot s
LEFT JOIN laundry_order l ON l.slot_id = s.slot_id AND l.status <> 'CANCELLED'
WHERE  s.slot_id = RACE_SLOT
GROUP BY s.capacity;
```
```
[paste real output here — expect capacity=5, used=6, free_spaces=-1  <-- OVERBOOKED]
```

**Why it happened (write the explanation after you see the bug):**

> Both transactions ran under READ COMMITTED. Each `SELECT count(*)` saw only
> the 4 committed rows; the other transaction's uncommitted `INSERT` was
> invisible. So both passed the `4 < 5` check and inserted. After both
> committed, the slot held 6 orders against a capacity of 5. The capacity
> trigger fired for each `INSERT` but used the same naive count, so it also
> saw 4 and allowed the insert. This is the classic *read-modify-write* race,
> exactly the scenario the course notes describe under consistency models
> (Study Session 2).

### Step 1.5 — reset the fixture before the fix

```sql
ROLLBACK;   -- if any session is still open
-- reset to 4/5:
DELETE FROM laundry_order WHERE slot_id = RACE_SLOT AND customer_id IN
  (SELECT customer_id FROM customer WHERE email IN
    ('race1@example.com','race2@example.com'));
```
```
[paste real output here — DELETE 2  (the two extra orders removed)]
```

Re-confirm the slot is back to 4/5:

```sql
SELECT s.capacity, count(l.order_id) AS used
FROM pickup_slot s LEFT JOIN laundry_order l
       ON l.slot_id = s.slot_id AND l.status <> 'CANCELLED'
WHERE s.slot_id = RACE_SLOT GROUP BY s.capacity;
```
```
[paste real output here — expect capacity=5, used=4]
```

---

## Part 2 — FIX 1: `SELECT ... FOR UPDATE` on the slot row

`SELECT ... FOR UPDATE` takes a row-level lock on the slot. The second session's
`FOR UPDATE` **blocks** until the first session commits (or rolls back). When the
lock is granted, the second session re-reads the row (under READ COMMITTED it
sees the latest committed data) and re-counts — it now sees 5/5 and rejects the
booking.

This is what the production function `book_pickup()` (defined in
`01_book_pickup_function.sql`) does — its key line is
`SELECT * FROM pickup_slot WHERE slot_id = p_slot_id FOR UPDATE;`.

### Step 2.1 — both sessions BEGIN, but the first one locks the slot

**Terminal A:**
```sql
BEGIN;
SELECT * FROM pickup_slot WHERE slot_id = RACE_SLOT FOR UPDATE;
```
```
[paste real output here — A sees the slot row and now HOLDS the row lock]
```

### Step 2.2 — Terminal B tries to lock the SAME slot — it BLOCKS

**Terminal B:**
```sql
BEGIN;
SELECT * FROM pickup_slot WHERE slot_id = RACE_SLOT FOR UPDATE;
```
```
[paste real output here — the prompt does NOT return; B is waiting for A's lock]
```

(Leave B waiting. Switch back to A.)

### Step 2.3 — Terminal A counts, inserts and commits

**Terminal A:**
```sql
SELECT count(*) AS a_count FROM laundry_order
 WHERE slot_id = RACE_SLOT AND status <> 'CANCELLED';
-- expect 4
INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
SELECT (SELECT customer_id FROM customer WHERE email='race1@example.com'),
       RACE_SLOT, (SELECT outlet_id FROM outlet WHERE area_id=1 LIMIT 1),
       'BOOKED', now(), '1 Race Rd, Lekki';
COMMIT;
```
```
[paste real output here — A commits and releases the lock; B's SELECT FOR UPDATE now wakes up]
```

### Step 2.4 — Terminal B wakes up, re-counts, and is rejected

**Terminal B** (the waiting `SELECT ... FOR UPDATE` now returns):
```
[paste real output here — B's SELECT FOR UPDATE finally returns the slot row]
```

Now B re-counts (sees the freshly committed 5/5):
```sql
SELECT count(*) AS b_count FROM laundry_order
 WHERE slot_id = RACE_SLOT AND status <> 'CANCELLED';
```
```
[paste real output here — expect b_count = 5  (the slot is now full)]
```

B sees the slot is full and rejects the booking:
```sql
INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
SELECT (SELECT customer_id FROM customer WHERE email='race2@example.com'),
       RACE_SLOT, (SELECT outlet_id FROM outlet WHERE area_id=1 LIMIT 1),
       'BOOKED', now(), '2 Race Rd, Lekki';
```
```
[paste real output here — the capacity trigger now sees 5 committed rows and rejects: ERROR: Slot RACE_SLOT is full (5 / 5). Booking rejected.]
```

Roll B back and confirm the slot is exactly 5/5 (NOT 6/5):
```sql
ROLLBACK;
SELECT s.capacity, count(l.order_id) AS used
FROM pickup_slot s LEFT JOIN laundry_order l
       ON l.slot_id = s.slot_id AND l.status <> 'CANCELLED'
WHERE s.slot_id = RACE_SLOT GROUP BY s.capacity;
```
```
[paste real output here — expect capacity=5, used=5  (CORRECT, no overbooking)]
```

**Why FIX 1 works:** `FOR UPDATE` serialises access to the slot row. The second
transaction cannot even *start* its read-modify-write until the first has
committed, so the second's count is always fresh.

### Step 2.5 — reset the fixture again

```sql
DELETE FROM laundry_order WHERE slot_id = RACE_SLOT AND customer_id IN
  (SELECT customer_id FROM customer WHERE email = 'race1@example.com');
-- back to 4/5
```

### Step 2.6 — the same fix, using the production function

You can reproduce FIX 1 in one line using `book_pickup()`:

**Terminal A:**
```sql
BEGIN;
SELECT book_pickup(
  (SELECT customer_id FROM customer WHERE email='race1@example.com'),
  RACE_SLOT,
  '[{"garment_type":"shirt","quantity":1,"service":"wash_iron","unit_price":600}]'::jsonb,
  'card', 600.00, false);
-- leave the transaction open
```
```
[paste real output here — A holds the slot lock]
```

**Terminal B** (in a second session, while A is still open):
```sql
BEGIN;
SELECT book_pickup(
  (SELECT customer_id FROM customer WHERE email='race2@example.com'),
  RACE_SLOT,
  '[{"garment_type":"trouser","quantity":1,"service":"wash_iron","unit_price":700}]'::jsonb,
  'card', 700.00, false);
```
```
[paste real output here — B BLOCKS, then once A commits, B wakes up and raises: ERROR: Slot RACE_SLOT is full (5 / 5). Booking rejected.]
```

**Terminal A:**
```sql
COMMIT;
```
```
[paste real output here]
```

Confirm 5/5, then reset:
```sql
DELETE FROM laundry_order WHERE slot_id = RACE_SLOT AND customer_id IN
  (SELECT customer_id FROM customer WHERE email='race1@example.com');
-- back to 4/5
```

---

## Part 3 — FIX 2: `SERIALIZABLE` isolation level with a retry

Under `SERIALIZABLE`, PostgreSQL tracks each transaction's read set and write
set, and at `COMMIT` time it detects a **read/write conflict** between
concurrent transactions. The transaction that commits last (or the one
Postgres picks) is aborted with `serialization_failure` (SQLSTATE `40001`).
The client must then **retry in a NEW transaction** (a new snapshot), re-count,
and act on the fresh data.

> A PL/pgSQL function **cannot** start a new transaction, so the retry must
> happen at the client level. In production, a client library (psycopg2, JDBC,
> .NET) catches `40001` and re-issues the whole call. The guide below does the
> retry by hand, exactly as a client library would.

### Step 3.1 — both sessions BEGIN with SERIALIZABLE and count

**Terminal A:**
```sql
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT count(*) AS a_count FROM laundry_order
 WHERE slot_id = RACE_SLOT AND status <> 'CANCELLED';
```
```
[paste real output here — expect a_count = 4]
```

**Terminal B:**
```sql
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT count(*) AS b_count FROM laundry_order
 WHERE slot_id = RACE_SLOT AND status <> 'CANCELLED';
```
```
[paste real output here — expect b_count = 4]
```

### Step 3.2 — both INSERT

**Terminal A:**
```sql
INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
SELECT (SELECT customer_id FROM customer WHERE email='race1@example.com'),
       RACE_SLOT, (SELECT outlet_id FROM outlet WHERE area_id=1 LIMIT 1),
       'BOOKED', now(), '1 Race Rd, Lekki';
COMMIT;
```
```
[paste real output here — A commits first and SUCCEEDS]
```

**Terminal B:**
```sql
INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
SELECT (SELECT customer_id FROM customer WHERE email='race2@example.com'),
       RACE_SLOT, (SELECT outlet_id FROM outlet WHERE area_id=1 LIMIT 1),
       'BOOKED', now(), '2 Race Rd, Lekki';
COMMIT;
```
```
[paste real output here — B's COMMIT fails with: ERROR: could not serialize access due to read/write dependencies among transactions  (SQLSTATE 40001)]
```

### Step 3.3 — Terminal B RETRIES in a fresh SERIALIZABLE transaction

B's transaction is now aborted. Roll it back and start a brand-new one:

**Terminal B:**
```sql
ROLLBACK;
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT count(*) AS b_count_retry FROM laundry_order
 WHERE slot_id = RACE_SLOT AND status <> 'CANCELLED';
```
```
[paste real output here — expect b_count_retry = 5  (A's booking is now visible)]
```

B sees the slot is full and gives up gracefully:

```sql
-- The slot is full -> report "no space" to the customer (no insert).
SELECT 'Sorry, the slot is now full' AS outcome;
COMMIT;
```
```
[paste real output here]
```

Confirm the slot is exactly 5/5 (NOT 6/5):
```sql
SELECT s.capacity, count(l.order_id) AS used
FROM pickup_slot s LEFT JOIN laundry_order l
       ON l.slot_id = s.slot_id AND l.status <> 'CANCELLED'
WHERE s.slot_id = RACE_SLOT GROUP BY s.capacity;
```
```
[paste real output here — expect capacity=5, used=5  (CORRECT)]
```

**Why FIX 2 works:** SERIALIZABLE makes the database detect the conflict that
READ COMMITTED silently allowed. B's `count(*)` read the slot at 4, then A's
commit changed the data B had read. At B's `COMMIT`, Postgres sees that B's
read set was invalidated by A's write and aborts B with `40001`. The retry runs
in a fresh snapshot, sees 5, and correctly gives up.

### Step 3.4 — reset the fixture

```sql
DELETE FROM laundry_order WHERE slot_id = RACE_SLOT AND customer_id IN
  (SELECT customer_id FROM customer WHERE email='race1@example.com');
-- back to 4/5
```

---

## Summary — which fix to use?

| Fix | Mechanism | Pro | Con |
| --- | --- | --- | --- |
| FIX 1 `SELECT ... FOR UPDATE` | Row lock serialises access to the slot | Simple, fast, minimal contention for a single hot row | Locks reduce concurrency on the same slot; a long transaction holds the lock |
| FIX 2 `SERIALIZABLE` + retry | The DB detects the read/write conflict and aborts one txn; the client retries | No explicit locks; works for complex multi-row logic too | Higher abort rate under contention; the client MUST handle `40001` and retry |

For FreshFold, the slot-row lock (FIX 1) is the right default because each slot
is a single hot row and the critical section is tiny. SERIALIZABLE with retry is
the better choice when the booking decision spans several tables and a row
lock would be too coarse.

## Study session mapping

This guide applies:
* **Study Session 1** — the ACID foundations (Atomicity: COMMIT/ROLLBACK of the
  order+items+payment; Isolation: READ COMMITTED vs SERIALIZABLE; the
  limitations-of-traditional-DBMS discussion that motivates explicit locking).
* **Study Session 2** — consistency models (the read-modify-write race, the
  `SELECT FOR UPDATE` pessimistic lock, the SERIALIZABLE optimistic conflict
  detection, and the trade-off between the two).
