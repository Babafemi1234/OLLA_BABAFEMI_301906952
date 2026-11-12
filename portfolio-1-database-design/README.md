# Portfolio 1 — Database Design and Modelling

**Student:** Olla Babafemi · **Matric:** 2026/A/MIT/0111 · **Course:** MIT 8103 Advanced Database Systems
**Case study:** FreshFold Laundry (Lagos) · **Study session covered:** Study Session 1 — *Review of Traditional Relational Databases and Advanced Concepts* (DB design stages, normalisation, keys, constraints, NoSQL intro).

## What this portfolio demonstrates

This portfolio designs the full relational schema for the FreshFold Laundry case
study and proves that every business rule is enforced by the database itself, not
by application code. The nine core entities (the set the CA asks for) are
`area`, `outlet`, `customer`, `rider`, `pickup_slot`, `laundry_order`,
`order_item`, `payment`, and `delivery`, plus one helper entity
(`rider_assignment`) that lets us enforce the "a rider can't be assigned two
overlapping pickups OR deliveries" rule with a single `EXCLUDE USING gist`
constraint on a `tstzrange` (using `btree_gist`).

Constraints implemented and tested:

| Business rule | How it is enforced | Test |
| --- | --- | --- |
| A pickup slot may not accept more orders than its capacity | `BEFORE INSERT/UPDATE` trigger `enforce_slot_capacity` (naive guard; the concurrency hole is the subject of Portfolio 3) | Test 1 |
| A rider can't be assigned two overlapping pickups or deliveries | `EXCLUDE USING gist (rider_id WITH =, busy_range WITH &&)` on `rider_assignment`, kept in sync by triggers 3 & 4; `btree_gist` lets a scalar column sit inside the gist `EXCLUDE` | Tests 2 & 3 |
| Delivery time must be after pickup time | `CHECK (delivered_at > picked_up_at)` on `delivery`, plus monotonic timestamp CHECKs on `laundry_order` | Test 4 |
| `quantity > 0` on order items | `CHECK (quantity > 0)` | Tests 5 & 5b |
| `payment.amount > 0` | `CHECK (amount > 0)` | Tests 6 & 6b |
| Order status follows `BOOKED → PICKED_UP → WASHING → READY → DELIVERED` or branches to `CANCELLED` (terminal) | `BEFORE UPDATE OF status` trigger `enforce_status_transition` | Tests 7, 8 & 9 |
| Pickup window must be exactly 2 hours | `CHECK (window_end = window_start + 2 hours)` | Test 10 |
| Vehicle and service must be from an allowed set | `CHECK` constraints | Tests 11 & 12 |
| At most one payment per order | `UNIQUE (order_id)` on `payment` | Test 13 |

## Files in this folder

| File | Purpose |
| --- | --- |
| `01_schema.sql` | Creates all tables, constraints, triggers, and the `EXCLUDE USING gist` constraint. Idempotent. |
| `02_er_diagram.md` | ER diagram in Mermaid (`erDiagram`) with every entity, its key columns and the constraints. Renders on GitHub. |
| `03_normalisation_notes.md` | Table-by-table 3NF justification, including the deliberate decisions NOT to denormalise aggregates or flexible per-garment attributes (those go to MongoDB in Portfolio 4). |
| `04_seed_data.sql` | Seeds 5 areas, 5 outlets, 30 customers, 12 riders and ~900 pickup slots for the next 30 days (relative to `CURRENT_DATE`). |
| `05_bulk_generator.py` | Generates **50,000+ orders over 2 years** with realistic Nigerian names, Lagos addresses and ₦ prices. Capacity-aware and rider-exclusion-safe. |
| `06_constraint_tests.sql` | 13 tests; each performs an invalid operation and asserts the constraint rejects it (prints `PASS`). |
| `run_p1.sh` | Runs the four steps above end-to-end through the Unix socket. |

## Exact Codespaces commands

```bash
# from the repository root, after running setup.sh once:
cd advanced-database-portfolio
./portfolio-1-database-design/run_p1.sh
```

Or step by step:

```bash
cd advanced-database-portfolio/portfolio-1-database-design

# 1. create the schema
psql -h /var/run/postgresql -U freshfold -d freshfold -v ON_ERROR_STOP=1 -f 01_schema.sql

# 2. seed the dimension tables and starter slots
psql -h /var/run/postgresql -U freshfold -d freshfold -v ON_ERROR_STOP=1 -f 04_seed_data.sql

# 3. generate 50,000+ orders
python3 05_bulk_generator.py

# 4. run the constraint tests (each MUST be rejected; the script prints PASS)
psql -h /var/run/postgresql -U freshfold -d freshfold -v ON_ERROR_STOP=1 -f 06_constraint_tests.sql
```

## What to screenshot (for the LMS submission evidence)

1. The Mermaid ER diagram rendered on GitHub (open `02_er_diagram.md` on GitHub
   and screenshot the rendered diagram).
2. The terminal output of `python3 05_bulk_generator.py` showing the final
   summary block:
   - `orders : 5xxxx`, `order items : ...`, `payments : ...`,
     `deliveries : ...`, `rider assignments : ...`
   - `slots over capacity: 0   (MUST be 0)`
   - the status breakdown (`DELIVERED / CANCELLED / READY / WASHING / PICKED_UP / BOOKED`)
3. The terminal output of `06_constraint_tests.sql` showing every test line
   `PASS test N: ...`. All 13 tests must say `PASS` (the script only succeeds if
   every bad operation was rejected).
4. (Optional) `\d laundry_order` and `\d rider_assignment` in `psql` to show the
   trigger list and the EXCLUDE constraint definition.

> Where this README says "the script prints X", paste your **real** captured
> output into the final documentation. Never invent or simulate the numbers —
> the bulk generator prints the actual counts from your database.

## git commit (run from the repository root)

```bash
git add portfolio-1-database-design/
git commit -m "Portfolio 1: FreshFold Laundry schema, ER diagram, 3NF notes, 50k+ bulk orders, constraint tests"
git push
```

## Plain-English explanation

FreshFold Laundry is a Lagos on-demand laundry service. A customer books a
pickup *slot* (an area, a date, a 2-hour window, with a fixed capacity). A rider
collects the dirty clothes, an outlet washes and irons them, the customer pays
(per item or per bag, in Naira), and a rider delivers the clean clothes back.

The schema models this flow with nine tables. The interesting design decisions
are:

* **Capacity is enforced by a trigger** that counts the active orders already in
  a slot and rejects an over-capacity booking. This is a naive row-level guard —
  Portfolio 3 will show that under concurrent transactions two sessions can both
  read "4/5 used" and both insert, leaving the slot at 6/5, and then fix it with
  `SELECT ... FOR UPDATE` and with `SERIALIZABLE` isolation plus a retry.
* **Rider non-overlap is enforced by an EXCLUDE constraint on a `tstzrange`**,
  not by application code. We keep a helper table `rider_assignment` whose every
  row carries the rider's *busy range* (`tstzrange`). Two triggers keep it in
  sync — one when an order is given a `pickup_rider_id` (busy range = the slot's
  2-hour window), one when a delivery row is created (busy range = the delivery
  trip `[picked_up_at, delivered_at]`). The single constraint
  `EXCLUDE USING gist (rider_id WITH =, busy_range WITH &&)` then forbids any two
  overlapping assignments for the same rider — pickup-vs-pickup,
  delivery-vs-delivery, or pickup-vs-delivery. `btree_gist` is the extension
  that lets a plain scalar column (`rider_id`) be combined with a range column
  inside one gist `EXCLUDE`.
* **The order lifecycle is enforced by a status-transition trigger** that only
  accepts `BOOKED → PICKED_UP → WASHING → READY → DELIVERED` and the branch
  `BOOKED → CANCELLED`. `CANCELLED` and `DELIVERED` are terminal.
* **Delivery time after pickup time** is enforced by CHECK constraints on both
  `delivery` (`delivered_at > picked_up_at`) and `laundry_order` (monotonic
  lifecycle timestamps).
* **The bulk generator never lets a slot exceed capacity** and never lets a
  rider's assignments overlap, by construction — pickup riders are a disjoint
  pool from delivery riders, a pickup rider is used at most once per
  `(date, window)`, and delivery trips are scheduled with a per-rider cursor.
  The generator prints `slots over capacity: 0` as proof.
* **Flexible per-garment fields** (photo, stains, fabric type, special care)
  are intentionally *not* modelled here — they belong to the document model in
  Portfolio 4, where each garment type can have a different set of fields. This
  is the SQL-vs-NoSQL trade-off discussed in Study Session 1.

## Study session mapping

This portfolio applies **Study Session 1 (Review of Traditional Relational
Databases and Advanced Concepts)**, specifically:
* section 1.1.1 — Introduction to Database System Design (the schema design),
* section 1.7 — Normalisation (the 3NF notes),
* section 1.5–1.6 — Components and characteristics of a good database (the
  constraints and triggers),
* the limitations-of-traditional-DBMS discussion (which motivates Portfolio 4's
  document model for the flexible per-garment fields).
