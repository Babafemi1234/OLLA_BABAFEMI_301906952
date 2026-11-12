# Portfolio 3 — Isolation levels demo (two-terminal guide)

**Student:** Olla Babafemi · **Matric:** 2026/A/MIT/0111 · **Course:** MIT 8103 Advanced Database Systems
**Case study:** FreshFold Laundry (Lagos) · **Study sessions covered:** Study Session 1 (ACID) + Study Session 2 (consistency models).

PostgreSQL offers four isolation levels. The three that matter for this
portfolio are **READ COMMITTED** (the default), **REPEATABLE READ** (snapshot
isolation) and **SERIALIZABLE** (snapshot isolation + SSI conflict detection).
This guide shows the observable difference between them on the FreshFold
schema, using two `psql` sessions.

> **Honesty rule.** Every `[paste real output here]` slot is for YOUR captured
> output. Run the commands in two real windows and paste what you see.

Open two `psql` sessions (Terminal A and Terminal B):

```bash
psql -h /var/run/postgresql -U freshfold -d freshfold     # Terminal A
psql -h /var/run/postgresql -U freshfold -d freshfold     # Terminal B
```

Pick a target customer to read and modify (run in either terminal):

```sql
SELECT customer_id, address FROM customer WHERE email='race1@example.com';
```
```
[paste real output here — note the customer_id as CUST below]
```

---

## Demo 1 — READ COMMITTED allows a NON-REPEATABLE READ

Under READ COMMITTED, each statement sees a fresh snapshot of committed data.
If another transaction commits a change between two reads in the *same*
transaction, the second read returns the new value — a *non-repeatable read*.

### Step 1 — A begins (READ COMMITTED, the default) and reads the address

**Terminal A:**
```sql
BEGIN;
SELECT address FROM customer WHERE customer_id = CUST;
```
```
[paste real output here — note the address as ADDR_BEFORE]
```

### Step 2 — B updates the address and commits

**Terminal B:**
```sql
BEGIN;
UPDATE customer SET address = '1 Updated Street, Lekki' WHERE customer_id = CUST;
COMMIT;
```
```
[paste real output here]
```

### Step 3 — A reads the SAME row again

**Terminal A:**
```sql
SELECT address FROM customer WHERE customer_id = CUST;
```
```
[paste real output here — the address is NOW '1 Updated Street, Lekki', different from ADDR_BEFORE]
```

A saw two different values for the same row within ONE transaction →
**non-repeatable read** under READ COMMITTED.

```sql
COMMIT;
-- restore the address for the next demo
UPDATE customer SET address = '1 Race Rd, Lekki' WHERE customer_id = CUST;
```

---

## Demo 2 — REPEATABLE READ prevents the non-repeatable read

Under REPEATABLE READ, A's transaction uses a single snapshot taken at the
first read. All of A's later reads see that snapshot, regardless of what other
transactions commit.

### Step 1 — A begins REPEATABLE READ and reads the address

**Terminal A:**
```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT address FROM customer WHERE customer_id = CUST;
```
```
[paste real output here — note ADDR_BEFORE again]
```

### Step 2 — B updates the address and commits

**Terminal B:**
```sql
BEGIN;
UPDATE customer SET address = '2 Updated Street, Lekki' WHERE customer_id = CUST;
COMMIT;
```
```
[paste real output here]
```

### Step 3 — A reads the SAME row again — still sees the OLD value

**Terminal A:**
```sql
SELECT address FROM customer WHERE customer_id = CUST;
```
```
[paste real output here — the address is STILL ADDR_BEFORE, NOT '2 Updated Street, Lekki']
```

A saw the same value both times → no non-repeatable read under REPEATABLE
READ. The snapshot is frozen for the whole transaction.

```sql
COMMIT;
-- after A commits, a FRESH read would see the new value:
SELECT address FROM customer WHERE customer_id = CUST;
```
```
[paste real output here — now the fresh read shows '2 Updated Street, Lekki']
```

Restore the address:
```sql
UPDATE customer SET address = '1 Race Rd, Lekki' WHERE customer_id = CUST;
```

---

## Demo 3 — SERIALIZABLE detects the write conflict (see the race guide)

The full SERIALIZABLE conflict demonstration (where two transactions both
read a count, both act on it, and the second `COMMIT` is aborted with
`serialization_failure` SQLSTATE `40001`) is the subject of
**`03_race_condition_guide.md` Part 3**. The point of isolation levels is
summarised below.

| Isolation level | Snapshot | Prevents non-repeatable read? | Prevents phantoms? | Prevents write skew? | How |
| --- | --- | --- | --- | --- | --- |
| READ COMMITTED (default) | per-statement | No (Demo 1) | No | No | each statement sees latest committed |
| REPEATABLE READ | per-transaction | Yes (Demo 2) | Yes (snapshot) | No — Postgres RR is snapshot isolation | frozen snapshot |
| SERIALIZABLE | per-transaction + SSI | Yes | Yes | Yes | SSI aborts a conflicting txn at COMMIT with `40001` |

The SERIALIZABLE retry behaviour is demonstrated end-to-end in
`03_race_condition_guide.md` Part 3 (FIX 2).

---

## Study session mapping

This demo applies **Study Session 1** (the ACID properties — specifically the
*Isolation* property and how the four isolation levels trade consistency for
concurrency) and **Study Session 2** (consistency models — snapshot isolation
vs serializability, the trade-offs discussed under the CAP/ACID material).
