#!/usr/bin/env python3
"""
run_race_demos.py - Portfolio 3 two-session demos, run automatically.
Two REAL PostgreSQL sessions (psycopg2) play "Terminal A" and "Terminal B".
Every line printed is real output from this run (also saved by run_p3.sh to
race_demos_output.log). Parts: 1 bug, 2 FOR UPDATE fix, 3 SERIALIZABLE, 4 deadlock.
"""
import subprocess, threading, time, os, sys
import psycopg2

HERE = os.path.dirname(os.path.abspath(__file__))
DSN = "host=/var/run/postgresql dbname=freshfold user=freshfold"

def conn(iso=None):
    c = psycopg2.connect(DSN)
    if iso:
        c.set_session(isolation_level=iso)
    return c

def reset():
    subprocess.run(["psql", "-h", "/var/run/postgresql", "-U", "freshfold", "-d", "freshfold",
                    "-q", "-v", "ON_ERROR_STOP=1", "-f", os.path.join(HERE, "00_race_setup.sql")],
                   check=True, stdout=subprocess.DEVNULL)
    c = conn(); cur = c.cursor()
    cur.execute("SELECT slot_id FROM pickup_slot WHERE area_id=1 AND slot_date=CURRENT_DATE+21 AND window_start=time '10:00'")
    slot = cur.fetchone()[0]
    cur.execute("SELECT customer_id FROM customer WHERE email IN ('race1@example.com','race2@example.com') ORDER BY email")
    custs = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT outlet_id FROM outlet WHERE area_id=1 LIMIT 1")
    outlet = cur.fetchone()[0]
    c.close()
    return slot, custs, outlet

def used(slot):
    c = conn(); cur = c.cursor()
    cur.execute("SELECT count(*) FROM laundry_order WHERE slot_id=%s AND status<>'CANCELLED'", (slot,))
    n = cur.fetchone()[0]; c.close(); return n

def say(who, msg): print(f"  [{who}] {msg}", flush=True)

INS = ("INSERT INTO laundry_order (customer_id, slot_id, outlet_id, status, booked_at, delivery_address) "
       "VALUES (%s,%s,%s,'BOOKED',now(),'Race demo, Lekki')")
CNT = "SELECT count(*) FROM laundry_order WHERE slot_id=%s AND status<>'CANCELLED'"

def part1():
    print("\n=== PART 1 - the bug: check-then-insert at READ COMMITTED (slot capacity 5, 4 used) ===")
    slot, custs, outlet = reset()
    a, b = conn(), conn(); ca, cb = a.cursor(), b.cursor()
    ca.execute(CNT, (slot,)); say("A", f"counts {ca.fetchone()[0]} used of 5 -> looks free")
    cb.execute(CNT, (slot,)); say("B", f"counts {cb.fetchone()[0]} used of 5 -> looks free")
    ca.execute(INS, (custs[0], slot, outlet)); say("A", "INSERT booking (not committed yet)")
    cb.execute(INS, (custs[1], slot, outlet)); say("B", "INSERT booking (A's row is invisible to B)")
    a.commit(); say("A", "COMMIT"); b.commit(); say("B", "COMMIT")
    n = used(slot); print(f"  RESULT: {n} bookings in a slot of capacity 5  ->  {'OVERBOOKED (bug reproduced)' if n > 5 else 'not reproduced'}")
    a.close(); b.close()

def part2():
    print("\n=== PART 2 - fix 1: SELECT ... FOR UPDATE on the slot row (what book_pickup() does) ===")
    slot, custs, outlet = reset()
    a, b = conn(), conn(); ca, cb = a.cursor(), b.cursor()
    ca.execute("SELECT slot_id FROM pickup_slot WHERE slot_id=%s FOR UPDATE", (slot,)); say("A", "locked the slot row")
    res = {}
    def run_b():
        cb.execute("SELECT slot_id FROM pickup_slot WHERE slot_id=%s FOR UPDATE", (slot,))  # blocks
        cb.execute(CNT, (slot,)); n = cb.fetchone()[0]
        res["seen"] = n
        if n < 5:
            cb.execute(INS, (custs[1], slot, outlet)); res["booked"] = True
        else:
            res["booked"] = False
        b.commit()
    t = threading.Thread(target=run_b); t.start(); time.sleep(1)
    say("B", f"is waiting for A's lock (thread alive = {t.is_alive()})")
    ca.execute(CNT, (slot,)); say("A", f"counts {ca.fetchone()[0]} used -> free"); ca.execute(INS, (custs[0], slot, outlet))
    a.commit(); say("A", "COMMIT (lock released)")
    t.join()
    say("B", f"got the lock, counted {res['seen']} used -> {'booked' if res['booked'] else 'REJECTED: slot full'}")
    n = used(slot); print(f"  RESULT: {n} bookings, capacity 5  ->  {'correct, no overbooking' if n == 5 else 'UNEXPECTED'}")
    a.close(); b.close()

def part3():
    print("\n=== PART 3 - fix 2: SERIALIZABLE isolation (one session is told to retry) ===")
    slot, custs, outlet = reset()
    a, b = conn("SERIALIZABLE"), conn("SERIALIZABLE"); ca, cb = a.cursor(), b.cursor()
    ca.execute(CNT, (slot,)); say("A", f"counts {ca.fetchone()[0]} used")
    cb.execute(CNT, (slot,)); say("B", f"counts {cb.fetchone()[0]} used")
    ca.execute(INS, (custs[0], slot, outlet)); cb.execute(INS, (custs[1], slot, outlet))
    outcome = []
    for who, c in (("A", a), ("B", b)):
        try:
            c.commit(); outcome.append(f"{who} COMMIT ok"); say(who, "COMMIT ok")
        except psycopg2.Error as e:
            c.rollback(); outcome.append(f"{who} failed {e.pgcode}"); say(who, f"COMMIT refused, SQLSTATE {e.pgcode}: {str(e).splitlines()[0]}")
    n = used(slot); print(f"  RESULT: {n} bookings, capacity 5  ->  {'correct (the loser must retry)' if n == 5 else 'UNEXPECTED'}")
    a.close(); b.close()

def part4():
    print("\n=== PART 4 - deadlock: A locks slot 1 then 2, B locks slot 2 then 1 ===")
    slot, custs, outlet = reset()
    c0 = conn(); cur = c0.cursor()
    cur.execute("SELECT slot_id FROM pickup_slot WHERE area_id=1 AND slot_date=CURRENT_DATE+21 ORDER BY slot_id LIMIT 2")
    s1, s2 = [r[0] for r in cur.fetchall()]; c0.close()
    a, b = conn(), conn(); ca, cb = a.cursor(), b.cursor()
    UPD = "UPDATE pickup_slot SET capacity = capacity WHERE slot_id=%s"
    ca.execute(UPD, (s1,)); say("A", f"locked slot {s1}")
    cb.execute(UPD, (s2,)); say("B", f"locked slot {s2}")
    out = {}
    def go(who, c, cu, sid):
        try:
            cu.execute(UPD, (sid,)); c.commit(); out[who] = "ok"
        except psycopg2.Error as e:
            c.rollback(); out[who] = f"{e.pgcode} {str(e).splitlines()[0]}"
    ta = threading.Thread(target=go, args=("A", a, ca, s2)); ta.start(); time.sleep(0.3)
    tb = threading.Thread(target=go, args=("B", b, cb, s1)); tb.start()
    ta.join(); tb.join()
    for k in ("A", "B"): say(k, out[k])
    dead = [k for k in out if out[k].startswith("40P01")]
    print(f"  RESULT: PostgreSQL killed {dead} with SQLSTATE 40P01; the other session completed.")
    print("  Fix: always lock slots in ascending slot_id order (then no cycle is possible).")
    a.close(); b.close()

if __name__ == "__main__":
    print("Portfolio 3 - concurrency demos (two real sessions)")
    for p in (part1, part2, part3, part4):
        p()
    reset()
    print("\nDone.")
