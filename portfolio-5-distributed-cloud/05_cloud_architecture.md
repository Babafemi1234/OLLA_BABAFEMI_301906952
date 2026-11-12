# Portfolio 5 — Cloud architecture, NDPA 2023, CAP, sync vs async, rider apps

**Student:** Olla Babafemi · **Matric:** 2026/A/MIT/0111 · **Course:** MIT 8103 Advanced Database Systems
**Case study:** FreshFold Laundry (Lagos) · **Study sessions covered:** Study Session 2 (distributed DB, CAP, ACID/BASE, fragmentation, replication) + Study Session 3 (cloud DB, big data) + Study Session 6 (data privacy / data security).

This note describes how FreshFold Laundry would deploy its database tier in
the cloud *while keeping customer data inside Nigeria*, explains the CAP and
sync-vs-async trade-offs that drive the design, and covers how the rider apps
keep working when the mobile network is poor (a daily reality for logistics in
Lagos). It builds on the two hands-on pieces in this portfolio — the monthly
**partitioning** (`01_partitioning.sql`) and the **primary + streaming read
replica** (`02_replica_setup.md`, `04_replica_test_guide.md`).

---

## 1. Architecture overview

```
                      ┌────────────────────────── Lagos region (NG) ──────────────────────────┐
                      │                                                                          │
   customer app ──┐   │   ┌──────────────────────────┐         ┌──────────────────────────┐   │
                  ├───┼──▶│  PostgreSQL PRIMARY (5432) │──WAL──▶ │ PostgreSQL READ REPLICA   │   │
   rider app ─────┤   │   │  - laundry_order (PARTITIONED          │  (5433, read-only)        │   │
                  │   │   │     by month)                          │  - analytics / heavy reads │   │
   outlet tablet ─┘   │   │  - capacity + rider EXCLUDE             └──────────────────────────┘   │
                      │   │    constraints, ACID transactions                                      │
                      │   └─────────────────┬────────────────────────────────────────────────────┘   │
                      │                     │ WAL (async, near-zero lag on LAN)                       │
                      │                     ▼                                                          │
                      │   ┌──────────────────────────┐                                              │
                      │   │  MongoDB REPLICA SET       │  ◀── garment photos, stains, fabric,       │
                      │   │  (primary + 2 secondaries) │      per-type care, damage complaints     │
                      │   │  - flexible schema         │                                              │
                      │   └──────────────────────────┘                                              │
                      │                                                                          │
                      │   local object storage (photos) + TLS + audit log, all in-region           │
                      └──────────────────────────────────────────────────────────────────────────┘
                                              data residency boundary (NDPA 2023)
```

The transactional core (PostgreSQL primary) holds the bookings, payments, slots
and the rider-overlap constraint. A **streaming read replica** offloads
analytics. The orders table is **partitioned by month** so old months can be
archived cheaply and the hot months' indexes stay small. The flexible
garment data lives in a **MongoDB replica set** (three members) so the
garment documents stay highly available even if one member fails. The
`order_id` is the join key between the two stores (polyglot persistence, as in
Portfolio 4). All of this runs **inside a single Lagos region** so customer
PII never leaves Nigeria.

---

## 2. Keeping data in Nigeria — NDPA 2023

The **Nigeria Data Protection Act 2023 (NDPA)** is the law that operationalises
the data-privacy principles taught in Study Session 6. It establishes the
Nigeria Data Protection Commission and requires data controllers and
processors to handle personal data lawfully, purposefully, securely, and with
accountability. For FreshFold, the relevant obligations are:

* **Data residency / local processing.** FreshFold's customers, riders and
  outlets are all in Lagos. Customer names, phone numbers, home addresses and
  payment references are *personal data* under the NDPA. The architecture
  therefore pins the PostgreSQL primary, the read replica, the MongoDB
  replica set and the photo object storage **to a Lagos cloud region** (for
  example, a Nigerian-located zone of a hyperscaler, or a local IaaS provider).
  No PII is replicated outside Nigeria for normal operations.
* **Cross-border transfer only with safeguards.** If a copy of the data ever
  needs to leave Nigeria (e.g. for disaster recovery in another country), the
  NDPA requires an adequate level of protection in the recipient country, or
  appropriate safeguards (standard contractual clauses, binding corporate
  rules, or the data subject's consent). The design's default is **no
  cross-border replication of PII**; a DR replica, if added, would be
  pseudonymised (names and phone numbers replaced by tokens that only the
  Lagos primary can re-identify).
* **Data subject rights.** A customer can request access, rectification,
  erasure ("right to be forgotten") and portability. The schema supports
  this: a customer's row plus their orders, items, payments and deliveries can
  be exported (portability) or deleted in a cascading transaction (erasure),
  and the MongoDB garment documents referencing that customer's `order_id`s
  can be deleted in the same workflow.
* **Purpose limitation and minimisation.** Photos are taken for
  damage-proof / dispute-resolution only; the schema's `damage_complaints`
  array is the only reason photos are linked to a garment. The retention
  policy would auto-delete photos (a TTL index on a `photo_expiry` field in
  MongoDB, or a scheduled purge in PostgreSQL) after the dispute window closes.
* **Security and breach notification.** The NDPA requires reasonable
  security and breach notification to the Commission and to affected data
  subjects within a defined window. FreshFold's design uses TLS in transit,
  encrypted-at-rest volumes, least-privilege roles (the `freshfold` role is
  NOT a production superuser — see the production note below), and an audit
  log of who accessed PII.
* **Data Protection Officer (DPO) and records of processing.** A DPO
  maintains the record of processing activities and is the contact for the
  Commission. Out of scope for the database itself, but the schema makes the
  processing auditable (every booking, payment and delivery has a timestamp
  and an actor).

> **Production note on roles.** In `setup.sh` the `freshfold` role is created
> as `SUPERUSER` for convenience in a one-user Codespace. In production it
> would be a plain role with `CONNECT` on the database and `SELECT/INSERT/
> UPDATE/DELETE` only on the tables it needs, plus a separate read-only role
> for the replica's analytics queries and a `replicator` role with only
> `REPLICATION` privilege. This is the least-privilege principle the NDPA
> expects.

---

## 3. CAP analysis — which two we pick, for which subsystem

The **CAP theorem** (Study Session 2) says a distributed system can guarantee
at most two of {Consistency, Availability, Partition tolerance} during a
network partition. Because partitions *do* happen (network glitches, a
replica crashing), partition tolerance is non-negotiable, so the real choice
is **CP vs AP** per subsystem:

| Subsystem | CAP choice | Why |
| --- | --- | --- |
| Bookings + payments + rider assignments (PostgreSQL primary) | **CP** | A booking must NEVER overbook a slot and a rider must NEVER be double-booked. The `EXCLUDE` constraint and the slot-capacity trigger from Portfolio 1, plus the `FOR UPDATE` / SERIALIZABLE fixes from Portfolio 3, give us strong consistency. If the primary is partitioned from its replica, the primary keeps accepting writes (it is the single source of truth); the replica goes stale but never accepts a conflicting write. We sacrifice a little availability: if the primary is down, writes are unavailable until it recovers (or a synchronous standby is promoted). |
| Analytics read replica | **AP (read side)** | The replica is allowed to lag, so a dashboard might show a few seconds' stale data — acceptable for reporting. It is *available* for reads even if the primary is briefly unreachable. |
| MongoDB garment documents (replica set) | **AP** | Garment photos, stains, fabric and care data are "write once, read many". Eventual consistency is fine: if a rider tags a stain and the network drops, the tag reaches the replica set as soon as the network returns. We accept a small window where two readers might see slightly different states of one garment in exchange for high availability. MongoDB replica sets default to eventual consistency across secondaries (reads from secondaries may lag), matching the AP choice. |
| Rider app local queue (offline) | **AP (client side)** | When the rider's phone has no network, the app MUST keep working (accept a pickup, mark "delivered"). It queues the action locally and syncs when the network returns. The bookings remain CP at the server: the app uses **idempotent** operations and the server reconciles using the SERIALIZABLE retry from Portfolio 3 to resolve conflicts. |

The trade-off is not "consistency everywhere" or "availability everywhere" —
it is *consistency where money and constraints are involved, availability
where user experience and poor networks are involved*.

---

## 4. Synchronous vs asynchronous replication

Streaming replication can be **synchronous** (the primary waits for the
replica to flush the WAL before reporting the transaction as committed) or
**asynchronous** (the primary commits immediately; the replica catches up
when it can). FreshFold uses both, per subsystem:

| What | Mode | Setting | Trade-off |
| --- | --- | --- | --- |
| Payment / booking core (no data loss tolerated) | **synchronous** to a local standby | `synchronous_standby_names = 'FIRST 1 (freshfold_sync)'` | The primary waits for the standby to flush. Higher write latency (one extra round-trip), but **zero data loss** if the primary crashes after commit. Availability: if the synchronous standby is down, the primary blocks writes — so we keep the standby in the same data centre (low latency) and accept that a double failure could pause writes. |
| Analytics read replica | **asynchronous** | default (`sync_state = async`, as seen in `pg_stat_replication`) | The primary commits without waiting. Low write latency, high read-scaling. Small window of data loss if the primary crashes before the last WAL ships — acceptable for analytics. |
| MongoDB replica set | **asynchronous** to secondaries by default; reads from primary are strongly consistent, reads from secondaries are eventually consistent | `writeConcern: {w: 1, j: true}` for important writes; `readPreference: primary` for strong reads, `secondaryPreferred` for dashboards | Same trade-off: strong for writes that matter, eventual for dashboards. |
| Cross-region DR copy (if added) | **asynchronous** + pseudonymised | logical replication with a delay option | DR copy is never on the synchronous path, so a Lagos outage does not block DR. Pseudonymisation keeps the NDPA happy. |

The hands-on replica in `03_replica_setup.sh` is asynchronous by default
(`sync_state = async` in `pg_stat_replication`), which is the right default for
a read-scaling replica. The synchronous mode is shown as a configuration
change in the note below, not run, because a synchronous standby requires a
second replica and would block the primary if the standby is down — risky in
a single-Codespace demo.

> To make the local replica synchronous in production, set
> `synchronous_standby_names = 'FIRST 1 (freshfold_replica)'` on the primary
> (the replica's `application_name` is set in its `primary_conninfo`), restart
> the primary, and verify `sync_state = sync` in `pg_stat_replication`. The
> trade-off (latency vs zero data loss) is exactly the ACID-vs-BASE discussion
> from Study Session 2.

---

## 5. Rider apps working with poor network

Lagos mobile networks drop in and out, and a rider is often in a basement or
a traffic jam with no signal. The app must keep working. The design is
**offline-first**:

1. **Local queue.** When the rider marks "picked up" or "delivered", the app
   writes the action to a local SQLite queue on the phone immediately (the UI
   shows "saved offline"). No network round-trip blocks the action.
2. **Idempotent operations.** Each action carries a client-generated
   idempotency key (`rider_id + order_id + action + client_nonce`). The
   server applies the action at most once, so a retry (network flaked mid-sync)
   does not double-count a pickup.
3. **Sync when network returns.** When the phone is back online, the app
   flushes the queue to the server. The server reconciles under
   **SERIALIZABLE** isolation (the same pattern as Portfolio 3's FIX 2): if
   two riders' syncs conflict (e.g., two riders assigned the same order),
   the server's conflict detection aborts one with `40001` and the app
   retries with fresh data.
4. **Last-write-wins for non-critical fields.** For garment photos and stain
   tags (the MongoDB side), the app uses a timestamp-based merge: the latest
   tag wins. This is AP at the document level.
5. **Server is the source of truth for money and capacity.** A booking is
   only "confirmed" when the server's `book_pickup()` (Portfolio 3) commits.
   The app shows a booking as "pending" until the server confirms; the
   slot-capacity trigger and the rider `EXCLUDE` constraint are the final
   authority. The offline-first design only queues *optimistic* actions;
   the server reconciles them with strong consistency.
6. **Background sync + push.** The app registers for push notifications;
   when the server reconciles a queued action (or rejects it because the
   slot is now full), it pushes the result back. The rider sees "booking
   confirmed" or "sorry, slot just filled — pick another window".

This is the **AP** choice at the client edge, combined with the **CP** choice
at the server. The rider never sees a hard failure on a flaky network, and
the database never lets a slot overbook. The conflict resolution is the same
mechanism Portfolio 3 demonstrated end-to-end.

---

## 6. How the hands-on pieces of this portfolio fit the architecture

| Hands-on piece | Where it fits |
| --- | --- |
| `01_partitioning.sql` — orders partitioned by month | The hot months' indexes stay small; old months can be archived / detached. Partition pruning keeps the monthly revenue and turnaround queries cheap (Portfolio 2). |
| `02_replica_setup.md` + `03_replica_setup.sh` — streaming read replica | Read scaling for the analytics workload; the AP read side of the CAP table. |
| `04_replica_test_guide.md` — replica rejects writes, new rows stream over | Proves the replica is read-only by construction and that async replication delivers new rows in sub-second. |
| This note (`05_cloud_architecture.md`) | The NDPA 2023 residency argument, the CAP per-subsystem choices, the sync-vs-async trade-off, and the offline-first rider-app design. |

---

## 7. Study session mapping (summary)

* **Study Session 2** — distributed database architecture, data fragmentation
  (partitioning by month is horizontal range fragmentation), data replication
  (the streaming read replica), consistency models (CP vs AP per subsystem),
  the CAP theorem, and the ACID-vs-BASE / sync-vs-async trade-offs.
* **Study Session 3** — cloud database systems (the cloud deployment, read
  replicas as the standard cloud read-scaling pattern, big-data-style monthly
  partitioning for the orders fact table) and database security (TLS, encryption
  at rest, least-privilege roles, audit log).
* **Study Session 6** — data privacy: the **NDPA 2023** residency requirement,
  data subject rights, purpose limitation, minimisation, breach notification,
  and the DPO/accountability obligations, all applied to where FreshFold stores
  customer PII.
