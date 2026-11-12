# Portfolio 3 — Transactions and Concurrency

**Student:** Olla Babafemi · **Matric:** 2026/A/MIT/0111 · **Course:** MIT 8103 Advanced Database Systems
**Case study:** FreshFold Laundry (Lagos) · **Study sessions covered:** Study Session 1 (ACID foundations) + Study Session 2 (consistency models, CAP / ACID trade-offs).

## What this portfolio demonstrates

This portfolio shows, with real `psql` evidence, that FreshFold's booking flow is
safe under concurrency:

1. **`book_pickup()`** — a single transaction that checks the slot has space,
   creates the order, inserts the order items, records the payment, and returns
   the order id. A simulated payment failure rolls the whole transaction back.
2. **COMMIT / ROLLBACK** — three demos showing a successful commit, a rollback
   caused by a failed payment, and the "failed payment cancels the order"
   pattern (the order persists as `CANCELLED` with a `failed` payment for the
   audit trail).
3. **The "last space in a pickup slot" race condition** — a step-by-step,
   two-terminal guide that reproduces the over-booking bug (two sessions both
   read "4/5", both insert, slot ends up "6/5"), then fixes it two ways:
   - **FIX 1** — `SELECT ... FOR UPDATE` on the slot row (the second session
     blocks until the first commits, then re-counts and sees the slot is full).
   - **FIX 2** — `SERIALIZABLE` isolation level with a retry (the second
     `COMMIT` fails with `40001`; the client retries in a fresh transaction and
     sees the slot is full).
4. **Isolation levels** — a two-terminal demo of READ COMMITTED (allows a
   non-repeatable read) vs REPEATABLE READ (prevents it via a snapshot) vs
   SERIALIZABLE (detects the conflict).
5. **Deadlock demo** — a two-terminal demo of a classic two-row deadlock,
   showing PostgreSQL's automatic detection (`40P01`) and the consistent
   lock-ordering fix.

## Files in this folder

| File | Type | What it does |
| --- | --- | --- |
| `01_book_pickup_function.sql` | runnable SQL | Defines `book_pickup_naive()` (no lock — the bug) and `book_pickup()` (FOR UPDATE — fix 1). |
| `02_commit_rollback_demo.sql` | runnable SQL | Demo A (COMMIT), Demo B (ROLLBACK on payment failure), Demo C (failed payment cancels the order, persists as CANCELLED). |
| `00_race_setup.sql` | runnable SQL | Builds the 5-capacity slot with exactly 4 orders (4/5) used by the race guide. |
| `03_race_condition_guide.md` | two-terminal guide | The bug + FIX 1 (`FOR UPDATE`) + FIX 2 (`SERIALIZABLE` + retry). |
| `04_isolation_levels_guide.md` | two-terminal guide | READ COMMITTED vs REPEATABLE READ vs SERIALIZABLE on the same row. |
| `05_deadlock_demo_guide.md` | two-terminal guide | Two-row deadlock + `40P01`. |
| `run_p3.sh` | shell | Runs the single-session parts and tells you which two-terminal guide to follow next. |

## Exact Codespaces commands

```bash
# from the repository root, after Portfolio 1 has loaded the data:
cd advanced-database-portfolio
./portfolio-3-transactions-concurrency/run_p3.sh
```

Then, for the two-terminal parts, open two `psql` sessions:

```bash
# Terminal A
psql -h /var/run/postgresql -U freshfold -d freshfold
# Terminal B  (a separate window)
psql -h /var/run/postgresql -U freshfold -d freshfold
```

and follow, in order:
1. `03_race_condition_guide.md`
2. `04_isolation_levels_guide.md`
3. `05_deadlock_demo_guide.md`

Paste your real captured output into every `[paste real output here]` slot.

## What to screenshot (for the LMS submission evidence)

1. The `NOTICE` lines printed by `02_commit_rollback_demo.sql` (Demo A, B, C)
   showing the before/after counts and the persisted `CANCELLED` order.
2. The bug reproduction from `03_race_condition_guide.md` Part 1: the two
   `INSERT 0 1` lines and the final `capacity=5, used=6, free_spaces=-1`
   (the overbooked slot).
3. FIX 1 (Part 2): Terminal B *blocking* on `SELECT ... FOR UPDATE`, then
   waking up and being rejected with `Slot ... is full (5 / 5)`.
4. FIX 2 (Part 3): Terminal B's `COMMIT` failing with `could not serialize
   access ... SQLSTATE 40001`, and the retry showing `b_count_retry = 5`.
5. The isolation-levels demo: the non-repeatable read under READ COMMITTED and
   the stable read under REPEATABLE READ.
6. The deadlock demo: the `deadlock detected ... SQLSTATE 40P01` message and
   the surviving transaction committing.

> **Honesty rule.** Every result is a placeholder until you paste your real
> output. Never invent a count, a timing or an error message.

## git commit (run from the repository root)

```bash
git add portfolio-3-transactions-concurrency/
git commit -m "Portfolio 3: book_pickup() transaction, COMMIT/ROLLBACK, race condition (FOR UPDATE + SERIALIZABLE), isolation levels, deadlock"
git push
```

## Plain-English explanation

When a customer books the *last* free space in a pickup slot, two customers can
click "book" at the same moment. The naive code reads the current count ("4 of 5
used"), decides there is space, and inserts — but the two reads happen
concurrently, both see 4, and both insert, leaving the slot at 6/5. The capacity
trigger from Portfolio 1 does not help because it is the same naive check; it
only sees committed rows, and neither insert has committed yet.

The two fixes are the standard concurrency answers:

* **Lock the row you are about to change.** `SELECT ... FOR UPDATE` on the slot
  row makes the second request *wait* until the first commits. When it wakes up
  it re-reads the row (now 5/5) and refuses the booking. This is pessimistic
  locking — simple, fast for a single hot row.
* **Let the database detect the conflict.** Under `SERIALIZABLE` isolation,
  PostgreSQL tracks what each transaction read and wrote. When B's `COMMIT`
  would create a read/write dependency that could not have happened in any
  serial order, Postgres aborts B with `40001`. The client retries in a fresh
  transaction, re-reads (now 5/5), and refuses the booking. This is optimistic —
  no explicit locks, but the client must handle `40001`.

For FreshFold, the slot-row lock is the better default because each slot is a
single hot row and the critical section is tiny. The SERIALIZABLE + retry
pattern is the better choice when a booking decision spans several tables.

The deadlock demo shows the other failure mode of locking: if two
transactions take locks in opposite orders, each waits for the other.
PostgreSQL's detector breaks the cycle by aborting one; the application
retries. The fix is to always take locks in a consistent order.

## Study session mapping

This portfolio applies:
* **Study Session 1** — the ACID properties (Atomicity: COMMIT/ROLLBACK of the
  order+items+payment; Isolation: the four isolation levels; the
  limitations-of-traditional-DBMS discussion that motivates explicit locking).
* **Study Session 2** — consistency models (the read-modify-write race,
  pessimistic `FOR UPDATE` vs optimistic SERIALIZABLE conflict detection, and
  the trade-off between the two that the CAP / ACID material discusses).
