# Portfolio 3 — Deadlock demo (two-terminal guide)

**Student:** Olla Babafemi · **Matric:** 2026/A/MIT/0111 · **Course:** MIT 8103 Advanced Database Systems
**Case study:** FreshFold Laundry (Lagos) · **Study sessions covered:** Study Session 1 (ACID) + Study Session 2 (consistency models).

A **deadlock** happens when two transactions each hold a lock the other needs.
PostgreSQL detects deadlocks automatically and aborts one of the transactions
with `deadlock_detected` (SQLSTATE `40P01`), letting the other proceed. The
client must retry the aborted transaction.

This guide reproduces a classic two-row deadlock on the `customer` table:
Terminal A locks customer 1 then asks for customer 2; Terminal B locks customer
2 then asks for customer 1. Each waits for the other.

> **Honesty rule.** Every `[paste real output here]` slot is for YOUR captured
> output. Run the commands in two real windows and paste what you see.

Open two `psql` sessions:

```bash
psql -h /var/run/postgresql -U freshfold -d freshfold     # Terminal A
psql -h /var/run/postgresql -U freshfold -d freshfold     # Terminal B
```

Pick two customers (run in either terminal):

```sql
SELECT customer_id AS C1, address AS A1 FROM customer WHERE email='race1@example.com';
SELECT customer_id AS C2, address AS A2 FROM customer WHERE email='race2@example.com';
```
```
[paste real output here — note the two customer ids as C1 and C2 below]
```

---

## Step 1 — A locks C1, B locks C2

**Terminal A:**
```sql
BEGIN;
UPDATE customer SET address = 'A holds C1' WHERE customer_id = C1;
```
```
[paste real output here — UPDATE 1; A now holds the row lock on C1]
```

**Terminal B:**
```sql
BEGIN;
UPDATE customer SET address = 'B holds C2' WHERE customer_id = C2;
```
```
[paste real output here — UPDATE 1; B now holds the row lock on C2]
```

## Step 2 — A asks for C2 (waits), then B asks for C1 (deadlock!)

**Terminal A** (this blocks, waiting for B's lock on C2):
```sql
UPDATE customer SET address = 'A wants C2' WHERE customer_id = C2;
```
```
[paste real output here — the prompt does NOT return; A is waiting]
```

**Terminal B** (this is the move that closes the cycle):
```sql
UPDATE customer SET address = 'B wants C1' WHERE customer_id = C1;
```
```
[paste real output here — after ~1 second, PostgreSQL's deadlock detector fires and aborts ONE of the transactions:

ERROR:  deadlock detected
DETAIL:  Process ... waits for ShareLock on transaction ... blocked by process ....
HINT:  See server log for query details.
CONTEXT:  while updating tuple (....) in relation "customer"
SQLSTATE: 40P01
```

The transaction that received the error is now aborted. The OTHER transaction
(A, the one waiting on C2) now proceeds and succeeds.

## Step 3 — observe the outcome and clean up

In the terminal that was aborted (the one that printed the `deadlock detected`
error — typically Terminal B here):
```sql
ROLLBACK;
```
```
[paste real output here]
```

In the terminal that survived (typically Terminal A — the waiting UPDATE on C2
now returns):
```sql
-- A's waiting update now succeeds:
-- (the UPDATE on C2 has returned by now)
COMMIT;
```
```
[paste real output here]
```

Inspect the final addresses (one was updated by A, the other is unchanged):
```sql
SELECT customer_id, address FROM customer
 WHERE customer_id IN (C1, C2) ORDER BY customer_id;
```
```
[paste real output here — C1 = 'A holds C1', C2 = 'A wants C2']
```

Restore the addresses for re-running:
```sql
UPDATE customer SET address = '1 Race Rd, Lekki' WHERE customer_id = C1;
UPDATE customer SET address = '2 Race Rd, Lekki' WHERE customer_id = C2;
```

## Why it happened and how to avoid it

> Two transactions acquired locks in **opposite order** (A: C1→C2; B: C2→C1).
> That order forms a cycle, which Postgres's deadlock detector breaks by
> aborting one transaction. The classic fixes are:
>
> 1. **Acquire locks in a consistent order across the application.** If every
>    transaction locks customer rows in ascending `customer_id` order, no cycle
>    can form.
> 2. **Keep transactions short** so locks are held for less time.
> 3. **Retry on `40P01`.** A client library should catch `deadlock_detected`
>    and re-issue the whole transaction, just like the SERIALIZABLE retry in
>    the race guide catches `40001`.

## Study session mapping

This demo applies **Study Session 1** (the *Consistency* and *Isolation*
properties, lock-based concurrency control and its deadlock failure mode) and
**Study Session 2** (consistency models — the trade-off between locking,
contention and deadlock risk that the CAP/ACID material discusses).
