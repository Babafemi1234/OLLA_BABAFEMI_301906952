# Normalisation notes — FreshFold Laundry (3NF)

Portfolio 1 · MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111

This document explains, table by table, why each relation in the FreshFold
Laundry schema is in **Third Normal Form (3NF)** and which non-normalised design
it avoids. The shorthand used below:

* **1NF** — every column holds a single atomic value; each row has a primary key.
* **2NF** — 1NF + no partial-key dependency (only relevant for composite keys).
* **3NF** — 2NF + no transitive dependency: every non-key column depends on
  *the key, the whole key, and nothing but the key*.

The course notes (Study Session 1, section 1.7 "Normalisation") define the same
three steps. The notes also list "limitations of traditional DBMS" — the
flexible-schema requirement that motivates Portfolio 4 (MongoDB) is exactly the
"garment-specific fields (photo, stains, fabric, special care)" case that is
hard to model in strict 3NF without a wide sparse table or an EAV table.

---

## Why each table is 3NF

### area
* **Atomic** name, lga, region (single text each).
* **Key:** `area_id` (surrogate PK). A `UNIQUE` constraint on `lga` enforces the
  natural key too.
* **Non-key columns** `name`, `lga`, `region` describe the area and nothing else.
  There is no transitive dependency (`region` describes the *area*, not the
  `lga`-of-an-area in a chain).
* **3NF.** The non-normal alternative would be to store `lga` and `region`
  repeated as free-text inside `outlet`/`customer` rows (update anomaly: rename
  a region and you'd touch thousands of rows). Pulling the area out fixes that.

### outlet
* Columns: `name`, `area_id`, `address`, `phone`.
* **Key:** `outlet_id`. `area_id` is a FK, not a transitive dependency — it
  references `area` which holds the area's own attributes.
* We do **not** denormalise area name/region into outlet; we join to `area` when
  we need them. → **3NF**.

### customer
* Columns: `full_name`, `phone`, `email`, `area_id`, `address`.
* **Key:** `customer_id`. The area is referenced, not embedded, so there is no
  transitive dependency (we never store `area_name` on the customer).
* `email` and `phone` describe the customer only. → **3NF**.

### rider
* Columns: `full_name`, `phone`, `vehicle`, `home_area_id`, `active`.
* **Key:** `rider_id`. `vehicle` is an attribute of the rider, not of any
  parent. `home_area_id` is a FK. → **3NF**.

### pickup_slot
* Columns: `area_id`, `slot_date`, `window_start`, `window_end`, `capacity`.
* **Key:** `slot_id`, plus a `UNIQUE (area_id, slot_date, window_start)`
  natural key.
* `window_end` is constrained to `window_start + 2 hours`, which is technically
  derivable — but we keep it as a stored, validated column for query clarity and
  to drive the `tstzrange` construction in the trigger. This is an intentional,
  documented, CHECK-protected redundancy, not a 3NF violation (it doesn't depend
  on anything outside the row).
* `capacity` is an attribute of the slot. → **3NF**.

### laundry_order
* The central fact table. Foreign keys to `customer`, `slot`, `outlet`,
  `pickup_rider`, `delivery_rider`. Own attributes: `status`, the lifecycle
  timestamps (`booked_at`, `picked_up_at`, `washing_started_at`, `ready_at`,
  `delivered_at`), `delivery_address`.
* **Key:** `order_id`.
* We deliberately do **not** store derived aggregates here (e.g. total order
  value) — that is computed by the `v_order_revenue` view from `order_item`.
* The lifecycle timestamps are all attributes of *this order's* lifecycle, so
  they belong on `laundry_order`; they are not transitive dependencies on a
  parent table. → **3NF**.
* Non-normal alternative avoided: putting `customer_name`, `outlet_name`,
  `area_name` directly on the order (would create update anomalies whenever a
  name changes).

### order_item
* Columns: `order_id` (FK), `garment_type`, `quantity`, `service`,
  `unit_price`, `line_total`.
* **Key:** `item_id`. `order_id` is a FK.
* `line_total` is a **stored generated column** = `quantity * unit_price`. It
  is derived from columns of the *same row*, which is allowed under 3NF (it is
  not a transitive dependency on another entity, and it cannot drift out of
  sync with the row). The CA requirement "quantity > 0" and "payment amount >
  0" are enforced with CHECK constraints.
* The flexible per-garment attributes (photo, stains, fabric type, special
  care) are deliberately **not** modelled here — they live in MongoDB (Portfolio
  4) because each garment type needs a *different* set of fields. Forcing them
  into 3NF SQL would require either a wide sparse table (dozens of mostly-NULL
  columns) or an EAV pattern (slow, query-hostile). The document model is the
  correct tool, which is exactly the SQL-vs-NoSQL trade-off Study Session 1
  discusses. → **3NF for the relational slice.**

### payment
* Columns: `order_id` (FK, UNIQUE), `amount`, `method`, `status`, `reference`,
  `paid_at`.
* **Key:** `payment_id`. `order_id` is UNIQUE so an order has at most one
  payment.
* `amount > 0` is a CHECK. All columns describe the payment, not the order or
  the customer. → **3NF**.

### delivery
* Columns: `order_id` (FK, UNIQUE), `rider_id` (FK), `picked_up_at`,
  `delivered_at`, `signature`.
* **Key:** `delivery_id`. `order_id` is UNIQUE so an order has at most one
  delivery.
* `delivered_at > picked_up_at` is a CHECK. The rider is referenced, not
  embedded. → **3NF**.

### rider_assignment (helper entity for the exclusion constraint)
* Columns: `rider_id` (FK), `order_id` (FK), `kind`, `busy_range`.
* **Key:** `assignment_id`. `UNIQUE (order_id, kind)` ensures at most one
  pickup and one delivery assignment per order.
* `busy_range` is a `tstzrange` derived from the slot window (pickup) or the
  delivery window (delivery). Storing it as a column is what makes the
  `EXCLUDE USING gist (rider_id WITH =, busy_range WITH &&)` constraint
  possible — you cannot index a computed expression for exclusion as cleanly.
* This is a **3NF** relation: every column depends on the key
  (`assignment_id`), and `busy_range` is a materialised representation of facts
  that already live in the parent rows, kept in sync by triggers. The
  materialisation is a deliberate, integrity-controlled choice, not a denormalisation
  that can drift.

---

## Normalisation decisions the schema deliberately does NOT make

1. **No denormalised aggregates.** Order totals, monthly revenue, and "busiest
   rider" are all computed by Portfolio 2 queries and the `v_order_revenue`
   view, never stored on the parent rows. This avoids update anomalies at the
   cost of query-time aggregation — the standard 3NF trade-off.
2. **No flexible per-garment attributes in SQL.** The garment-specific fields
   (photo URLs, stains, fabric type, special care) are intentionally pushed to
   MongoDB (Portfolio 4). They satisfy the document model's "different fields
   per garment" requirement cleanly, which strict 3NF SQL cannot.
3. **`line_total` and `window_end` are stored-derived.** Both are computed from
   other columns of the same row and protected by a generated-column rule or a
   CHECK constraint. They are kept because they make the queries and the
   `tstzrange` construction straightforward, and they cannot drift out of sync.

---

## Summary table

| Table | Key | Notable constraints | Normal form |
| --- | --- | --- | --- |
| area | area_id | unique lga | 3NF |
| outlet | outlet_id | FK area | 3NF |
| customer | customer_id | FK area | 3NF |
| rider | rider_id | FK area, vehicle CHECK | 3NF |
| pickup_slot | slot_id (unique area+date+window) | 2-hour window, capacity > 0 | 3NF |
| laundry_order | order_id | 5 FKs, status CHECK, monotonic timestamps | 3NF |
| order_item | item_id | quantity > 0, generated line_total | 3NF (stored-derived col) |
| payment | payment_id (unique order_id) | amount > 0 | 3NF |
| delivery | delivery_id (unique order_id) | delivered_at > picked_up_at | 3NF |
| rider_assignment | assignment_id (unique order+kind) | EXCLUDE gist (rider_id =, range &&) | 3NF (materialised helper) |
