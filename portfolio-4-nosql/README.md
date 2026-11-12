# Portfolio 4 — NoSQL and Advanced Data Models

**Student:** Olla Babafemi · **Matric:** 2026/A/MIT/0111 · **Course:** MIT 8103 Advanced Database Systems
**Case study:** FreshFold Laundry (Lagos) · **Study sessions covered:** Study Session 1 (NoSQL / NewSQL types, document model, NoSQL-vs-NewSQL) + Study Session 5 (graph databases, emerging trends).

## What this portfolio demonstrates

FreshFold stores the **transactional core** (orders, payments, slots, riders,
the capacity + exclusion constraints) in PostgreSQL, and the **flexible
per-garment-type attributes** in MongoDB. This portfolio builds the MongoDB
side: a `garments` collection whose documents carry photos, stains, fabric
type and a `care` sub-document whose **fields depend on the garment type**
(agbada → `starch` + `iron_temp` + `fold_style`; duvet → `machine_size` +
`detergent` + `dry_time_mins`; suit → `dry_clean_only` + `press_only`; ankara →
`hand_wash_only` + `no_bleach`), plus damage complaints.

It then runs three aggregations on the document data, demonstrates the
COLLSCAN → IXSCAN transition by adding a `garment_type` index, and explains the
SQL-vs-NoSQL trade-off in `05_sql_vs_nosql_comparison.md`.

## Files in this folder

| File | Purpose |
| --- | --- |
| `01_schema_validation.js` | Drops and recreates `freshfold.garments` with a `$jsonSchema` validator (envelope enforced; per-type `care` left flexible). |
| `02_seed_mongo.py` | Builds 40,000+ garment documents from the PostgreSQL `order_item` rows (photos, stains, fabric, per-type `care`, damage complaints) and bulk-inserts into MongoDB. |
| `03_aggregations.js` | Three aggregations: most common stains, care requests per fabric, damage complaints per outlet (count + top issue + overall). |
| `04_index_demo.js` | Runs `find({garment_type:"agbada"}).explain("executionStats")` BEFORE and AFTER creating `{garment_type:1}`, prints `totalDocsExamined` and `executionTimeMillis` (real numbers). |
| `05_sql_vs_nosql_comparison.md` | Short SQL-vs-NoSQL comparison for the FreshFold case study. |
| `run_p4.sh` | Runs all four steps end-to-end. |

## Exact Codespaces commands

```bash
# from the repository root, after Portfolio 1 has loaded the data and setup.sh
# has started MongoDB:
cd advanced-database-portfolio
./portfolio-4-nosql/run_p4.sh
```

If your Codespace started mongod with auth, export the URI first:

```bash
export MONGO_URI="mongodb://freshfold:freshfold@127.0.0.1:27017/freshfold"
./portfolio-4-nosql/run_p4.sh
```

Or step by step:

```bash
cd advanced-database-portfolio/portfolio-4-nosql
mongosh mongodb://127.0.0.1:27017/freshfold 01_schema_validation.js
python3 02_seed_mongo.py
mongosh mongodb://127.0.0.1:27017/freshfold 03_aggregations.js
mongosh mongodb://127.0.0.1:27017/freshfold 04_index_demo.js
```

## What to screenshot (for the LMS submission evidence)

1. `mongosh` output of `02_seed_mongo.py` showing
   `garments.count_documents({}) = NNNNN` (MUST be ≥ 40000) and the per-garment-type
   `care` examples (showing different fields per type).
2. `mongosh` output of `03_aggregations.js` — the three result arrays
   (most common stains, care requests per fabric, damage complaints per outlet).
3. `mongosh` output of `04_index_demo.js` — the BEFORE line with
   `leaf = COLLSCAN, totalDocsExamined = ~NNNNN` and the AFTER line with
   `leaf = IXSCAN, totalDocsExamined = NNN` (much smaller), plus the SUMMARY.

> **Honesty rule.** Every number in the screenshots is produced by your own run.
> Never invent a document count, an `executionTimeMillis`, or an aggregation
> result. The scripts print real numbers; capture them.

## git commit (run from the repository root)

```bash
git add portfolio-4-nosql/
git commit -m "Portfolio 4: MongoDB garment documents, schema validation, 40k+ docs, aggregations, COLLSCAN->IXSCAN, SQL vs NoSQL"
git push
```

## Plain-English explanation

The order_item table in PostgreSQL records *which* garments were in an order
and *how many*, with a price. But each garment type also carries a different
set of care instructions, a different fabric, sometimes photos taken before and
after cleaning, sometimes stains the customer flagged, and sometimes a damage
complaint if something went wrong. Forcing all of that into 3NF SQL would mean
either ~30 mostly-NULL care columns (a wide sparse table) or an
entity-attribute-value table that is miserable to query. MongoDB's document
model handles it naturally: one document per garment, with a `care` sub-document
that carries exactly the fields that garment needs.

The `$jsonSchema` validator enforces the *envelope* (every garment must have an
`order_id`, a `garment_type` from an allowed list, a `fabric_type`, a
`quantity ≥ 1`, a `service`, arrays of stains/photos/damage complaints and a
`care` object). The *per-garment-type* fields inside `care` are intentionally
flexible, which is the whole point of using a document database here.

The aggregations answer real operations questions: which stains do we see most
(helps the outlets stock the right stain removers), which fabrics drive the
hand-wash / dry-clean-only load (helps capacity planning), and which outlets
get the most damage complaints (helps target quality training). The
COLLSCAN → IXSCAN demo shows that without the `garment_type` index the query
reads the whole 40k+ collection, and with the index it reads only the matching
documents — the same access-path lesson as Portfolio 2's `EXPLAIN ANALYZE`,
but in MongoDB's planner.

The `order_id` on every garment document is the join key back to PostgreSQL, so
a report can combine the two stores by that id — polyglot persistence, with each
store doing the part it is best at.

## Study session mapping

This portfolio applies:
* **Study Session 1** — sections 1.9–1.12: the concept of NoSQL, the four NoSQL
  types (we use the **document** type), and the NoSQL-vs-NewSQL comparison
  (the `05_sql_vs_nosql_comparison.md` note).
* **Study Session 5** — section 5.2.1: graph databases and knowledge graphs
  (the relational FK graph between outlets, areas, orders, items, payments and
  deliveries is naturally graph-shaped, which is why a graph database is also a
  reasonable fit for the relationship layer — though FreshFold's transactional
  needs keep that layer in PostgreSQL).
