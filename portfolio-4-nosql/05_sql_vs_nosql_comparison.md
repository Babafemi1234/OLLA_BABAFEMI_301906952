# SQL vs NoSQL comparison — FreshFold Laundry

**Portfolio 4 · MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111**
**Study sessions covered:** Study Session 1 (NoSQL / NewSQL types and the NoSQL-vs-NewSQL comparison) + Study Session 5 (graph databases and emerging trends).

FreshFold Laundry uses **both** a relational database (PostgreSQL) and a document
database (MongoDB), each for the part of the data it is best at. This short note
explains why, and compares the two models on the FreshFold data.

## What lives where, and why

| Concern | PostgreSQL (relational) | MongoDB (document) |
| --- | --- | --- |
| Outlets, areas, customers, riders, slots, orders, payments, deliveries | ✔ the core transactional system | — |
| Order items (garment type, quantity, service, price) | ✔ a thin relational slice (`order_item`) | — |
| Per-garment flexible attributes: photos, stains, fabric type, **care flags that differ per garment type** (agbada → starch + iron_temp + fold_style; duvet → machine_size + detergent + dry_time_mins; suit → dry_clean_only + press_only; ankara → hand_wash_only + no_bleach) | ✗ would need a wide sparse table or an EAV table — query-hostile and rigid | ✔ a natural document: each garment is one doc whose `care` sub-document carries exactly the fields that garment needs |
| Damage complaints (free-form issue + severity + refund, evolving list of issue types) | ✗ a rigid enum + refund column; new issue types need a schema migration | ✔ a flexible array of sub-documents |
| Booking, payment, rider-assignment transactions with strict ACID + exclusion constraints | ✔ PostgreSQL's strong transactional guarantees and `EXCLUDE USING gist` | ✗ MongoDB multi-document transactions exist but are heavier and the relational constraints (FK, EXCLUDE) do not exist |
| Aggregations across the whole history (most common stains, care requests per fabric, damage per outlet) | possible but the per-garment-type columns make the SQL long and brittle | ✔ a clean aggregation pipeline over the document model |

The split is deliberate: **the relational side owns the money and the
constraints** (a slot can never be overbooked, a rider can never be double-booked,
an order's status must follow the lifecycle, a payment must be positive), while
**the document side owns the messy, evolving, per-garment-type attributes** that
would force constant schema migrations in SQL.

## Side-by-side comparison

| Dimension | PostgreSQL (relational / SQL) | MongoDB (document / NoSQL) |
| --- | --- | --- |
| Data model | tables, rows, strict schema, normalised to 3NF | BSON documents, flexible schema, $jsonSchema validator on the envelope only |
| Schema | enforced by the DB (CHECK, FK, UNIQUE, EXCLUDE, triggers) | enforced by a $jsonSchema validator on common fields; per-garment-type `care` is intentionally flexible |
| Joins | cheap, declarative (`JOIN`), the planner optimises them | no server-side joins; you either embed (as we do for stains/care) or `$lookup` (slower) |
| Transactions | first-class, ACID, fine-grained row locks, `SERIALIZABLE`, `EXCLUDE USING gist` | multi-document ACID since 4.0, but heavier; no FK / EXCLUDE / trigger-equivalent |
| Querying | SQL, with `EXPLAIN (ANALYZE)` cost estimation | JSON query objects + aggregation pipeline; `explain("executionStats")` shows COLLSCAN vs IXSCAN |
| Indexing | B-tree, GiST, GIN, partial, covering, expression indexes | B-tree, compound, text, geospatial, TTL; partial and wildcard indexes |
| Schema evolution | `ALTER TABLE` migrations, can be expensive at scale | add a field by inserting it; old documents simply lack it (read code must handle absence) |
| Best fit here | orders, payments, slots, riders, the capacity + exclusion constraints | garment photos, stains, fabric, per-type `care`, damage complaints |
| Weakness for FreshFold | cannot cleanly model "different fields per garment type" without an EAV or sparse-column anti-pattern | cannot enforce the slot-capacity or rider-overlap rule; weaker cross-document consistency |
| Scaling model | vertical first, then read replicas + declarative partitioning (Portfolio 5) | horizontal sharding built in; replica sets are the native HA unit |

## The per-garment-type care fields — the decisive example

In PostgreSQL, modelling that *an agbada needs `starch` + `iron_temp` +
`fold_style`*, *a duvet needs `machine_size` + `detergent` + `dry_time_mins`*,
and *a suit needs `dry_clean_only` + `press_only`* would force one of:

* a **wide sparse table** (`order_item` with ~30 mostly-NULL care columns, one
  per possible attribute — rigid, wastes space, every new garment type needs a
  migration); or
* an **entity-attribute-value table** (`(item_id, care_attribute, care_value)` —
  query-hostile, no type safety, slow aggregations).

In MongoDB the `care` sub-document simply carries whatever fields that garment
needs, and the aggregation pipeline handles the per-fabric counts with
`$sum` + `$cond`. The `$jsonSchema` validator still enforces the *envelope*
(order_id, garment_type, fabric_type, quantity, service, arrays of stains /
photos / damage) so we do not lose all structure — we lose only the rigid
per-type column set, which is exactly the part that should be flexible.

## When FreshFold would NOT use MongoDB

* The booking, payment and rider-assignment logic MUST stay in PostgreSQL. The
  `EXCLUDE USING gist (rider_id WITH =, busy_range WITH &&)` constraint cannot
  be expressed in MongoDB, and neither can the slot-capacity trigger that
  Portfolio 1 + Portfolio 3 rely on.
* Any report that needs strict consistency across the order, its items and its
  payment (e.g. "exactly how much was paid for this order") is computed in
  PostgreSQL, where the FK graph guarantees the rows exist.

## When FreshFold would NOT use PostgreSQL

* The garment-specific care attributes, photos and damage complaints — those
  live in MongoDB because forcing them into 3NF would either bloat the schema
  (sparse columns) or wreck query performance (EAV).

## Conclusion

The right answer for FreshFold is **polyglot persistence**: PostgreSQL for the
transactional core with strong constraints, MongoDB for the flexible,
per-garment-type document data. The `order_id` is the join key between the two:
every MongoDB garment document carries the `order_id` (and `item_id`) of its
PostgreSQL row, so a report can join the two stores by that id. This is the
SQL-vs-NoSQL trade-off that Study Session 1's NoSQL / NewSQL sections and Study
Session 5's emerging-trends material describe.

## Study session mapping

This comparison applies:
* **Study Session 1** — section 1.9–1.12: the concept of NoSQL, the four NoSQL
  types (we use the **document** type), and the NoSQL-vs-NewSQL comparison.
* **Study Session 5** — section 5.2.1: graph databases and knowledge graphs
  (the relational FK graph between outlets, areas, orders, items, payments and
  deliveries is naturally graph-shaped, which is why a graph database is also a
  reasonable fit for the relationship layer — though FreshFold's transactional
  needs keep it in PostgreSQL).
