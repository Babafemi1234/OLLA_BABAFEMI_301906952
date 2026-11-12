# Portfolio 5 — Streaming replica test (read-only + new rows arrive)

**Student:** Olla Babafemi · **Matric:** 2026/A/MIT/0111 · **Course:** MIT 8103 Advanced Database Systems
**Case study:** FreshFold Laundry (Lagos) · **Study sessions covered:** Study Session 2 (replication, consistency, CAP) + Study Session 3 (cloud DB).

This guide shows, with real `psql` evidence, the two defining behaviours of a
streaming physical replica:

1. **The replica rejects writes** — it is a read-only standby, so any `INSERT`
   / `UPDATE` / `DELETE` raises `cannot execute ... in a read-only transaction`.
2. **New rows written on the primary arrive on the replica** — streaming
   replication ships the WAL, so within a fraction of a second (near-zero on
   the same host) the row is visible on the replica.

> **Honesty rule.** Every `[paste real output here]` slot is for YOUR captured
> output. Run the commands and paste what you actually see.

Prerequisite: `03_replica_setup.sh` has run and both instances are up
(see `02_replica_setup.md`).

Open two `psql` sessions — one on the primary (5432), one on the replica (5433):

```bash
# Terminal PRIMARY
sudo runuser -u postgres -- psql -p 5432 -d freshfold

# Terminal REPLICA  (a separate window)
sudo runuser -u postgres -- psql -p 5433 -d freshfold
```

> The `freshfold` role is a SUPERUSER on the primary. On the replica, read
> queries work for any role; write queries fail because the instance is in
> standby mode. We connect over the Unix socket (`-p 5432` / `-p 5433` with
> the default socket dir), so no password is needed.

---

## Part A — the replica REJECTS writes

### Step A.1 — confirm the replica is in recovery (read-only)

**Terminal REPLICA:**
```sql
SELECT pg_is_in_recovery() AS in_recovery;
```
```
[paste real output here — expect in_recovery = t]
```

### Step A.2 — attempt a write on the replica; it MUST be rejected

**Terminal REPLICA:**
```sql
INSERT INTO area (name, lga, region) VALUES ('Write-Test Area', 'TestLGA', 'Mainland');
```
```
[paste real output here — expect:
ERROR:  cannot execute INSERT in a read-only transaction
SQLSTATE: 25006
]
```

The same happens for `UPDATE` and `DELETE`:
```sql
UPDATE area SET region = 'Island' WHERE name = 'Lekki';
```
```
[paste real output here — expect the same ERROR: 25006 cannot execute UPDATE in a read-only transaction]
```

### Step A.3 — reads on the replica work fine

**Terminal REPLICA:**
```sql
SELECT count(*) FROM laundry_order;
```
```
[paste real output here — expect the same count as on the primary]
```

This is the read replica's whole purpose: the analytics queries from Portfolio 2
(and the heavy monthly aggregations) can be sent to the replica so the primary
keeps serving transactional writes without competing for CPU and I/O.

---

## Part B — new rows written on the PRIMARY ARRIVE on the replica

### Step B.1 — note the current count on both instances

**Terminal PRIMARY:**
```sql
SELECT count(*) AS primary_count FROM laundry_order;
```
```
[paste real output here — note PRIMARY_COUNT]
```

**Terminal REPLICA:**
```sql
SELECT count(*) AS replica_count FROM laundry_order;
```
```
[paste real output here — note REPLICA_COUNT — should equal PRIMARY_COUNT]
```

### Step B.2 — insert a new order on the primary (committed)

**Terminal PRIMARY:**
```sql
-- a fresh slot for the new order, in the future so it satisfies the constraints
INSERT INTO pickup_slot (area_id, slot_date, window_start, window_end, capacity)
VALUES (1, CURRENT_DATE + 30, time '08:00', time '10:00', 5)
ON CONFLICT (area_id, slot_date, window_start) DO UPDATE SET capacity = EXCLUDED.capacity;

SELECT slot_id AS new_slot_id FROM pickup_slot
 WHERE area_id=1 AND slot_date=CURRENT_DATE+30 AND window_start=time '08:00' \gset

INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address)
SELECT (SELECT customer_id FROM customer WHERE email='p3@example.com'),
       :new_slot_id,
       (SELECT outlet_id FROM outlet WHERE area_id=1 LIMIT 1),
       'BOOKED', now(), 'Replica Test, Lekki'
RETURNING order_id AS new_order_id \gset

SELECT :new_order_id AS inserted_order_id;
```
```
[paste real output here — note the NEW_ORDER_ID]
```

### Step B.3 — the replica sees the new row (within a fraction of a second)

**Terminal REPLICA** (run immediately after Step B.2):
```sql
SELECT count(*) AS replica_count_after FROM laundry_order;
SELECT order_id, status, delivery_address
FROM   laundry_order
WHERE  order_id = <paste the NEW_ORDER_ID from step B.2>;
```
```
[paste real output here — expect:
 replica_count_after = PRIMARY_COUNT + 1
 the row with the NEW_ORDER_ID is visible on the replica
]
```

### Step B.4 — confirm replication lag is tiny

**Terminal REPLICA:**
```sql
SELECT now() - pg_last_xact_replay_timestamp() AS lag;
```
```
[paste real output here — expect a small interval, often under 1 second on the same host]
```

**Terminal PRIMARY:**
```sql
SELECT application_name, state, sync_state, sent_lsn, replay_lsn
FROM   pg_stat_replication;
```
```
[paste real output here — state='streaming', sent_lsn and replay_lsn close/equal]
```

### Step B.5 — clean up the test row (on the primary)

**Terminal PRIMARY:**
```sql
DELETE FROM laundry_order WHERE order_id = <NEW_ORDER_ID>;
```
```
[paste real output here]
```

**Terminal REPLICA** (confirm the delete also streamed):
```sql
SELECT count(*) AS replica_count_final FROM laundry_order;
```
```
[paste real output here — expect PRIMARY_COUNT again (the test row is gone from both)]
```

---

## What this demonstrates

* **Read scaling**: the replica can serve `SELECT`s, so heavy analytics
  (Portfolio 2 queries, the partitioned monthly aggregations) can be pointed
  at the replica without slowing the primary's transactional writes.
* **Asynchronous streaming**: the replica receives WAL continuously; on the
  same host the lag is sub-second. In production, across a network, the lag is
  bounded by the network and by the synchronous-commit setting.
* **The replica is read-only by construction**: standby mode rejects writes
  with `25006`. There is no application-level check needed; the database
  enforces it.
* **CAP and the sync-vs-async trade-off**: with **asynchronous** streaming
  (the default, `sync_state = async`), the primary commits without waiting for
  the replica, so availability and latency are preserved — but if the primary
  crashes before the last WAL reaches the replica, those last few transactions
  are lost (a small window of data loss). With **synchronous** replication
  (`synchronous_standby_names` set, `sync_state = sync`), the primary waits for
  the replica to flush the WAL before reporting commit — strong consistency at
  the cost of higher write latency and a loss of availability if the replica
  is down. This is exactly the CAP / ACID-vs-BASE trade-off Study Session 2
  discusses, and the cloud-architecture note (`05_cloud_architecture.md`)
  applies it to FreshFold's Nigerian deployment.

## Study session mapping

* **Study Session 2** — distributed database architecture, replication, the
  CAP theorem, the ACID-vs-BASE / sync-vs-async trade-offs.
* **Study Session 3** — cloud database systems (read replicas are the standard
  cloud pattern for read scaling and availability).
