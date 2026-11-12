# Advanced Database Systems Portfolio — FreshFold Laundry

**Student:** Olla Babafemi
**Matric number:** 2026/A/MIT/0111
**Programme:** Master of Information Technology, Miva Open University
**Course:** MIT 8103 Advanced Database Systems
**Academic session:** 2026/2027, First Semester Continuous Assessment (September 2026 cohort)
**GitHub repository:** `[paste your GitHub link here]`

---

## Case study (used consistently across all 5 portfolios)

**FreshFold Laundry** is a simulated on-demand laundry service operating in Lagos, Nigeria, with five outlets in Lekki, Ikeja, Yaba, Surulere and Ajah. The business flow modelled by this portfolio is:

1. A customer books a **pickup slot** (an area + a date + a 2-hour window, with a fixed capacity).
2. A **rider** is assigned to collect the customer's clothes within that window.
3. The clothes go to an **outlet**, where they are washed and ironed.
4. A **laundry_order** records the booking; each **order_item** captures a garment type, quantity and service (wash / wash+iron / dry-clean).
5. The customer makes a **payment** (per item or per bag, in Nigerian Naira ₦).
6. A rider **delivers** the cleaned clothes back to the customer; delivery time must be after pickup time.
7. Each order moves through a status flow:
   `BOOKED → PICKED_UP → WASHING → READY → DELIVERED`, or it can be `CANCELLED`.

This single case study supports database design (P1), query optimisation (P2), transactions and concurrency (P3), NoSQL modelling (P4) and distributed/cloud deployment (P5), so the five portfolios use the same organisation consistently as required by section 4 of the CA brief.

---

## Repository structure

```
advanced-database-portfolio/
├── README.md                         (this file)
├── setup.sh                          installs + starts PostgreSQL 16 and MongoDB 8
├── docs/
│   └── 00_brief_summary.md           CA brief summary + portfolio↔study-session map
├── portfolio-1-database-design/
├── portfolio-2-query-optimisation/
├── portfolio-3-transactions-concurrency/
├── portfolio-4-nosql/
└── portfolio-5-distributed-cloud/
```

Every portfolio folder contains:
* the SQL / Mongo / Python files for that portfolio,
* a `run_pN.sh` script that runs the whole portfolio end-to-end through the **Unix socket** (no passwords, no TCP),
* a `README.md` with the exact Codespaces commands, what to screenshot, the `git commit` command, a plain-English explanation of what it demonstrates, and the study session it covers.

---

## One-time environment setup (Codespaces)

Run this once in a fresh Codespace **before** running any portfolio:

```bash
# from the repository root
sudo bash setup.sh
```

`setup.sh` will:
1. remove `/etc/apt/sources.list.d/yarn.list` (stale Codespaces source that breaks `apt-get update`),
2. install and start **PostgreSQL 16** and **MongoDB 8**,
3. create the `freshfold` role + database (PostgreSQL) and the `freshfold` database + read user (MongoDB),
4. install the Python libraries used by the bulk generators (`psycopg2`, `pymongo`, `Faker`).

After it finishes, run the portfolios in order (each `run_pN.sh` is idempotent and safe to re-run):

```bash
./portfolio-1-database-design/run_p1.sh
./portfolio-2-query-optimisation/run_p2.sh
./portfolio-3-transactions-concurrency/run_p3.sh
./portfolio-4-nosql/run_p4.sh
./portfolio-5-distributed-cloud/run_p5.sh
```

---

## Codespaces rules (important — these are not optional)

The Codespaces default Ubuntu image handles services differently from a normal server. The scripts in this repo already follow these rules; do not change them:

1. **The codespace user can `sudo` only as root.** To run anything as the `postgres` OS user we use
   `sudo runuser -u postgres -- <command>` and never `sudo -u postgres <command>` (which would try to drop privileges to postgres first and fail).
2. **PostgreSQL config** lives in `/etc/postgresql/16/main/`, and the `pg_ctl` binary is `/usr/lib/postgresql/16/bin/pg_ctl`. Portfolio 5's streaming replica needs its own `postgresql.conf` copied from there.
3. **`pg_hba.conf` trust lines must go at the top of the file** — the first matching rule wins, so a later `scram-sha-256` rule would override an earlier trust rule that appears below it. Portfolio 5 prepends its trust lines.
4. **TCP logins require a password.** Every `psql` call in this repo connects through the **Unix socket** with `-h /var/run/postgresql`, so no password is needed locally. Do not switch to `-h localhost`.
5. **Do not use `postgres_fdw`** anywhere in the portfolio (the CA brief and this repo forbid it). Cross-database references are done by partitioning and replication instead.
6. **Remove `/etc/apt/sources.list.d/yarn.list` before `apt-get update`** — `setup.sh` already does this.
7. **Use dates relative to today.** All seed and bulk data use `CURRENT_DATE`, `NOW()`, and `generate_series(... CURRENT_DATE - interval '...')`, so the data set never "expires" when the portfolio is re-run months later. There are no hard-coded 2026-01-15 dates anywhere.

---

## Honesty rules

* This portfolio never invents or simulates any output, `EXPLAIN ANALYZE` plan, timing or screenshot.
* Where a real result belongs, the file says `[paste real output here]` so you paste your own captured output after running the command.
* The final 2–3 page documentation PDF (`Olla_Babafemi_2026-A-MIT-0111_Documentation.pdf`) is **not** included in this repo yet — it must be written only after you have run everything and collected real results, as instructed.

---

## AI use declaration (filled in the final documentation)

* **AI tool used:** `[fill in the final documentation]`
* **What it was used for:** `[fill in the final documentation]`
* **How the output was reviewed / corrected / tested:** `[fill in the final documentation]`

Every SQL/Mongo script, ER diagram and Markdown note in this repository was reviewed, edited, run and verified by the student before being committed. Simulated or invented output is never used.

---

## How each portfolio is graded (CA marking rubric, 40 marks total)

| Criteria | Marks |
| --- | --- |
| Technical correctness | 8 |
| Database design quality | 6 |
| Practical implementation | 8 |
| Query and performance analysis | 5 |
| Application of advanced database concepts | 5 |
| Documentation and GitHub organisation | 5 |
| Technical reflection / evidence of individual understanding | 3 |
| **Total** | **40** |

Per-portfolio marks: P1 = 7, P2 = 7, P3 = 7, P4 = 7, P5 = 6, Final Documentation = 6.

---

## Quick reference — connect to the databases

```bash
# PostgreSQL (Unix socket, no password)
psql -h /var/run/postgresql -U freshfold -d freshfold

# MongoDB
mongosh mongodb://freshfold:freshfold@127.0.0.1:27017/freshfold
# (or, if auth is off in your Codespace)
mongosh mongodb://127.0.0.1:27017/freshfold
```
