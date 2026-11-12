# Portfolio 5 — Streaming physical replica: setup guide

**Student:** Olla Babafemi · **Matric:** 2026/A/MIT/0111 · **Course:** MIT 8103 Advanced Database Systems
**Case study:** FreshFold Laundry (Lagos) · **Study sessions covered:** Study Session 2 (distributed DB, replication, CAP, ACID/BASE) + Study Session 3 (cloud database systems).

This guide sets up a **second PostgreSQL 16 instance** in the same Codespace
that acts as a **streaming physical replica** of the primary. The primary
stays on port 5432 (the existing cluster); the replica runs on port 5433.
The replica is read-only and continuously receives WAL records from the
primary over the Unix socket (no TCP, no password), exactly as a real
read replica would in production.

The automation script `03_replica_setup.sh` does the work; this document
explains each step so you can verify and screenshot it.

> **Codespaces rules honoured** (see repo README):
> * `sudo runuser -u postgres -- ...` is used everywhere (never `sudo -u postgres`);
> * the primary's config lives in `/etc/postgresql/16/main/` and the replica's
>   data dir is `/var/lib/postgresql/16/replica`;
> * the replica is started with `/usr/lib/postgresql/16/bin/pg_ctl` (not
>   `pg_ctlcluster`, which manages only the single main cluster);
> * the replication trust lines are prepended to the **top** of `pg_hba.conf`
>   so the first-match-wins rule keeps them in force;
> * replication and client connections go through the Unix socket
>   (`/var/run/postgresql`), so no TCP password is needed;
> * no `postgres_fdw` is used anywhere in this portfolio.

---

## Step 1 — run the setup script (with sudo)

```bash
cd advanced-database-portfolio/portfolio-5-distributed-cloud
sudo bash 03_replica_setup.sh
```

Expected tail output:
```
[paste real output here — expect "Replica setup complete." + the two verify commands]
```

What the script did (verify each one if anything fails):

### 1a. Primary replication settings (ALTER SYSTEM)

```sql
ALTER SYSTEM SET wal_level            = replica;
ALTER SYSTEM SET max_wal_senders      = 10;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET hot_standby          = on;
```
`wal_level = replica` lets the primary ship the information a replica needs.
`max_wal_senders` allows up to 10 replica connections. `hot_standby = on`
lets the replica answer read queries while it is recovering.

### 1b. pg_hba.conf trust lines prepended at the TOP

The script prepends this block to `/etc/postgresql/16/main/pg_hba.conf`:

```
# BEGIN freshfold-replica-trust (Portfolio 5) — must stay at the top
local   replication  replicator                              trust
local   all          all                                     trust
host    replication  replicator  127.0.0.1/32                trust
host    replication  replicator  ::1/128                     trust
host    all          all         127.0.0.1/32                 trust
# END freshfold-replica-trust
```

Because `pg_hba.conf` matches the **first** rule that fits, these trust lines
MUST be at the top — otherwise a later `scram-sha-256` rule would shadow them
and force a password, which the Unix-socket / TCP-from-127.0.0.1 connections
in Codespaces cannot supply.

Verify:
```bash
sudo head -n 8 /etc/postgresql/16/main/pg_hba.conf
```
```
[paste real output here — the trust block must be the first lines]
```

### 1c. Primary restarted

```bash
sudo pg_ctlcluster 16 main restart
```
The primary now accepts replication connections on the Unix socket.

### 1d. Replication role created

```sql
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replpass';
```

### 1e. Base backup taken over the Unix socket

```bash
sudo runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_basebackup \
  -h /var/run/postgresql -p 5432 -U replicator \
  -D /var/lib/postgresql/16/replica -Fp -Xs -P -R
```
`-R` writes a `standby.signal` file and a `primary_conninfo` line into
`/var/lib/postgresql/16/replica/postgresql.auto.conf`, so the replica knows it
is a standby and where to find the primary (over the Unix socket).

### 1f. Replica port override

The base backup copied the primary's `postgresql.conf` (which says
`port = 5432`). The script appends `port = 5433` to the replica's
`postgresql.auto.conf` so the replica listens on 5433 instead of clashing with
the primary. (`postgresql.auto.conf` overrides `postgresql.conf`.)

### 1g. Replica started with pg_ctl

```bash
sudo runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_ctl \
  -D /var/lib/postgresql/16/replica -l /var/log/postgresql/replica.log -w start
```
The replica is started with `pg_ctl` (not `pg_ctlcluster`) because
`pg_ctlcluster` manages only the single main cluster registered with the
Debian packaging. The copied `postgresql.conf` keeps
`unix_socket_directories = '/var/run/postgresql'`, so the replica creates
`/var/run/postgresql/.s.PGSQL.5433` and we connect over the socket.

---

## Step 2 — verify replication is streaming

On the **primary** (port 5432):
```bash
sudo runuser -u postgres -- psql -p 5432 -c \
  "SELECT application_name, client_addr, state, sync_state, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"
```
```
[paste real output here — expect one row with state='streaming', sync_state='async']
```

On the **replica** (port 5433):
```bash
sudo runuser -u postgres -- psql -p 5433 -c "SELECT pg_is_in_recovery();"
```
```
[paste real output here — expect t (= true, the replica is in recovery / standby mode)]
```

```bash
sudo runuser -u postgres -- psql -p 5433 -c \
  "SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;"
```
```
[paste real output here — expect a small interval (sub-second on the same host)]
```

If `pg_stat_replication` is empty, check the replica log:
```bash
sudo tail -n 50 /var/log/postgresql/replica.log
```
```
[paste real output here if you had to debug]
```

Common issues:
* `pg_hba.conf` trust lines not at the top → the replicator connection is
  rejected with a password prompt. Re-run `sudo bash 03_replica_setup.sh`,
  which prepends the trust block (it is idempotent on the marker).
* `port = 5432` left in the replica's `postgresql.auto.conf` → two instances
  try to bind the same port. The script overrides with `port = 5433`; if you
  edited the file by hand, make sure `5433` wins.

---

## Step 3 — move on to the read-only / streaming test

Open two `psql` sessions — one per instance — and follow
**`04_replica_test_guide.md`**:

```bash
# primary
sudo runuser -u postgres -- psql -p 5432 -d freshfold
# replica
sudo runuser -u postgres -- psql -p 5433 -d freshfold
```

The test guide shows the replica **rejecting writes** (it is read-only) and a
new row written on the primary **appearing on the replica** within a fraction
of a second (streaming replication, near-zero lag on the same host).

## What this demonstrates (study session mapping)

* **Study Session 2** — distributed database architecture, data replication
  and consistency models (synchronous vs asynchronous streaming, the CAP
  trade-off that the cloud architecture note discusses).
* **Study Session 3** — cloud database systems (a read replica is the
  standard cloud pattern for scaling reads and for availability).
