# Portfolio 5 — Distributed and Cloud Database Exercise

**Student:** Olla Babafemi · **Matric:** 2026/A/MIT/0111 · **Course:** MIT 8103 Advanced Database Systems
**Case study:** FreshFold Laundry (Lagos) · **Study sessions covered:** Study Session 2 (distributed DB, CAP, ACID/BASE, replication, fragmentation) + Study Session 3 (cloud DB, big data, database security) + Study Session 6 (data privacy / NDPA 2023).

## What this portfolio demonstrates

This portfolio shows three things, hands-on, plus the design discussion that
ties them together:

1. **Partitioning the orders table by month** — declarative RANGE partitioning
   on `booked_at`, with monthly partitions across the 2-year data span, data
   migrated from the flat table, and a partition-pruning `EXPLAIN` that shows
   only the relevant partition is scanned.
2. **A primary + streaming read replica** — a second PostgreSQL 16 instance on
   port 5433 that is a read-only streaming physical replica of the primary on
   5432. The replica rejects writes (`25006`) and new rows written on the
   primary appear on the replica within a fraction of a second.
3. **A cloud architecture that keeps data in Nigeria** — the NDPA 2023 data
   residency argument, the CAP per-subsystem choices, the sync-vs-async
   replication trade-off, and an offline-first design for the rider apps on
   poor Lagos mobile networks.

## Files in this folder

| File | Type | What it does |
| --- | --- | --- |
| `01_partitioning.sql` | runnable SQL | Builds the monthly-partitioned `laundry_order_p`, migrates the data, shows per-partition row counts and a partition-pruning `EXPLAIN`. |
| `02_replica_setup.md` | guide | Explains what `03_replica_setup.sh` does and how to verify the streaming replica is up. |
| `03_replica_setup.sh` | script (run with sudo) | Configures the primary for replication, prepends trust lines to the top of `pg_hba.conf`, takes a `pg_basebackup` over the Unix socket, starts the replica on port 5433 with `pg_ctl`. |
| `04_replica_test_guide.md` | two-terminal guide | Shows the replica rejecting writes and new rows streaming over. |
| `05_cloud_architecture.md` | discussion | The NDPA 2023 residency design, the CAP per-subsystem table, the sync-vs-async trade-off, and the offline-first rider-app design. |
| `run_p5.sh` | shell | Runs the partitioning demo, then prints the exact commands to set up and test the replica. |

## Exact Codespaces commands

```bash
# from the repository root, after Portfolios 1-4 have run:
cd advanced-database-portfolio
./portfolio-5-distributed-cloud/run_p5.sh          # partitioning demo

# then set up the streaming replica (needs sudo):
sudo bash portfolio-5-distributed-cloud/03_replica_setup.sh
```

Then open two `psql` sessions to verify and test the replica:

```bash
# Terminal PRIMARY
sudo runuser -u postgres -- psql -p 5432 -d freshfold
# Terminal REPLICA  (a separate window)
sudo runuser -u postgres -- psql -p 5433 -d freshfold
```

Follow `02_replica_setup.md` (verify replication is streaming) then
`04_replica_test_guide.md` (replica rejects writes; new rows stream over).

Read `05_cloud_architecture.md` for the NDPA 2023 / CAP / sync-vs-async /
rider-app discussion.

## What to screenshot (for the LMS submission evidence)

1. The per-partition row counts from `01_partitioning.sql` (showing the orders
   split by month).
2. The partition-pruning `EXPLAIN` from `01_partitioning.sql` (only the last
   3 months' partitions scanned) vs the full-scan `EXPLAIN` (every partition
   scanned).
3. `sudo head -n 8 /etc/postgresql/16/main/pg_hba.conf` showing the trust lines
   at the top.
4. The primary's `pg_stat_replication` showing `state = streaming` and
   `sync_state = async`.
5. The replica's `SELECT pg_is_in_recovery()` returning `t`.
6. The replica rejecting an `INSERT` with `ERROR: cannot execute INSERT in a
   read-only transaction (SQLSTATE 25006)`.
7. A row inserted on the primary (committed) then appearing on the replica,
   plus `now() - pg_last_xact_replay_timestamp()` showing a small lag.

> **Honesty rule.** Every result is a placeholder until you paste your real
> output. Never invent a row count, an LSN, or a lag value.

## git commit (run from the repository root)

```bash
git add portfolio-5-distributed-cloud/
git commit -m "Portfolio 5: monthly partitioning, primary + streaming read replica, NDPA 2023 cloud architecture, CAP and sync-vs-async"
git push
```

## Plain-English explanation

FreshFold's orders grow by ~25,000 a year. Keeping them in one flat table
means every monthly-revenue query scans two years of history. **Partitioning
the orders by month** lets PostgreSQL prune the query to only the months the
query asks for (a `WHERE booked_at` between two months touches only those
partitions), and old months can be detached and archived cheaply. The
`EXPLAIN` shows the pruning: a query for the last 3 months scans only those
three partitions, not the whole table.

The **streaming read replica** is the standard cloud pattern for read scaling
and availability. The primary (port 5432) takes the transactional writes and
enforces the capacity and rider-overlap constraints; the replica (port 5433)
serves the heavy analytics queries from Portfolio 2 so they do not compete
with bookings for CPU. The replica is **read-only by construction** —
PostgreSQL's standby mode rejects writes with `25006`, no application check
needed. New rows written on the primary ship over the WAL to the replica
within a fraction of a second on the same host.

The **cloud architecture** keeps all customer PII inside a Lagos region so
FreshFold complies with the **Nigeria Data Protection Act 2023** (the data
residency, data-subject-rights, minimisation and breach-notification
obligations from Study Session 6). The **CAP** choice is per subsystem:
consistency + partition tolerance for the booking/payment core (a slot can
never overbook, a rider can never be double-booked), availability + partition
tolerance for the analytics replica, the MongoDB garment documents and the
rider app. The **sync-vs-async** choice follows: the payment core replicates
synchronously to a local standby (zero data loss, higher latency), the
analytics replica and the MongoDB secondaries replicate asynchronously (low
latency, small data-loss window acceptable). The **rider app** is offline-first
— it queues actions locally on poor network and syncs when the network
returns, using idempotent operations and the SERIALIZABLE retry from
Portfolio 3 to reconcile conflicts at the server.

## Study session mapping

This portfolio applies:
* **Study Session 2** — distributed database architecture, data fragmentation
  (monthly range partitioning is horizontal fragmentation), replication (the
  streaming read replica), consistency models, the CAP theorem, and the
  ACID-vs-BASE / sync-vs-async trade-offs.
* **Study Session 3** — cloud database systems (the cloud deployment, read
  replicas as the standard cloud read-scaling pattern, big-data-style monthly
  partitioning for the orders fact table) and database security (TLS, encryption
  at rest, least-privilege roles, the audit log).
* **Study Session 6** — data privacy: the **NDPA 2023** residency requirement,
  data subject rights, purpose limitation, minimisation, breach notification,
  and the DPO/accountability obligations, applied to where FreshFold stores
  customer PII.
