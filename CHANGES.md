# CHANGES.md - FreshFold Laundry portfolio (Olla Babafemi, 2026/A/MIT/0111)

Claude tested the AI-generated project in a Codespaces-like environment (PostgreSQL 16, MongoDB 8, user with root-only sudo) and fixed what failed. Everything was kept simple and fast; the five portfolios and CA minimums are unchanged (63,000+ orders, 50,000 garment documents). The student runs everything in her own Codespace and the evidence comes from that run.

| # | File | Problem when run | Fix | Tested result |
|---|------|------------------|-----|---------------|
| 1 | setup.sh | The `freshfold` role was refused on the Unix socket (`Peer authentication failed`), so every runner died at step 1 | Adds `local all freshfold trust` at the top of pg_hba.conf and reloads; also sets the database time zone to Africa/Lagos | P1 connects and runs |
| 2 | setup.sh | `pip install --user` fails in Codespaces' Python, so psycopg2 may never install | Fallback chain (plain, `--user`, `--break-system-packages`, apt) and an import check at the end | Libraries verified |
| 3 | setup.sh | `apt-get update` failure (old keys) stopped the whole setup | `apt-get update` no longer aborts setup | n/a (Codespaces apt) |
| 4 | P1 06_constraint_tests.sql | Test 1: `column reference "outlet_id" is ambiguous` stopped all constraint tests | Renamed the PL/pgSQL variable | 13 tests, all PASS |
| 5 | P1 01_schema.sql | Status trigger fired only on UPDATE, so an INSERT with status WASHING was accepted (test 8 FAIL) | Trigger now `BEFORE INSERT OR UPDATE OF status` | test 8 PASS |
| 6 | P2 run_p2.sh | Not re-runnable: BEFORE run already had the optimisation indexes; no summary of timings | Drops the P2 indexes first, VACUUM ANALYZE after indexing (stable index-only scans), adds two selective queries (Q9, Q10), writes `explain_summary.txt` with real ms and scan types | Q1 about 25 ms to 0.3 ms, Q10 about 9 ms to 0.2 ms; the full-history queries stay Seq Scan (honest) |
| 7 | P3 02_commit_rollback_demo.sql | `:p3_slot_id` inside `DO $$` is not expanded by psql (`syntax error at or near ":"`) | Values passed through `set_config` / `current_setting` | Demo A, B, C run |
| 8 | P3 00_race_setup.sql | `c.addr` does not exist (column is `address`); a cross join could create several orders per customer | Uses `c.address` and one outlet | Slot starts at 4/5 |
| 9 | P3 two-terminal guides | Race, SERIALIZABLE and deadlock needed two hand-driven psql windows (timing cannot be reproduced by pasting) | New `run_race_demos.py` runs both sessions itself; `run_p3.sh` saves `race_demos_output.log` | Bug gives 6 bookings in a slot of 5; FOR UPDATE gives 5; SERIALIZABLE refuses one (40001); deadlock gives 40P01 |
| 10 | P4 01_schema_validation.js | `order_id` / `item_id` typed `long`, but they are stored as int, so every insert failed validation | `bsonType: ["int","long"]` | 50,000 documents inserted |
| 11 | P4 04_index_demo.js | `tojson is not defined` in script mode | Uses `JSON.stringify` | COLLSCAN 50,000 docs examined to IXSCAN 3,945 docs |
| 12 | P5 03_replica_setup.sh | `cat`/`grep` on pg_hba.conf without sudo (Permission denied); replica failed to start (`conf.d` not found); old replica not stopped as postgres | `sudo` on those reads; `include_dir` commented out in the replica conf; stop through `runuser` | Replica streams, `pg_is_in_recovery()` = true |
| 13 | P5 | Replica test was a manual two-terminal guide | New `06_replica_demo.sh` (one script): who is who, write rejected on replica, row streams over, lag, `pg_stat_replication`; `run_p5.sh` runs partitioning, replica and demo; DEFAULT partition row count printed | Output saved to `replication_output.log` |
| 14 | runall.sh (new) | Boxes pasted by hand break in chat apps | One script runs P1 to P5, commits each, stops with a clear message on failure, ends with `collect_results.sh` which writes `my_results.txt` | Rehearsed end to end |

Not changed on purpose: the data volume (about 30 s to generate), the five-portfolio structure, the case study. Left for the student to write: the reflection.
