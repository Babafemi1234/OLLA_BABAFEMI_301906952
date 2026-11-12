#!/usr/bin/env python3
# =============================================================================
# 05_bulk_generator.py  —  FreshFold Laundry bulk data generator
# Portfolio 1 · MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111
#
# Generates 50,000+ laundry orders spread across 2 years (relative to today,
# so the data never "expires"), with:
#   * realistic Nigerian names, Lagos addresses, and prices in Naira (₦),
#   * NO pickup slot ever over its capacity (the Python generator respects
#     capacity AND the SQL capacity trigger double-checks it),
#   * rider assignments that NEVER violate the EXCLUDE constraint:
#       - pickup riders are drawn from rider IDs 1..PICKUP_RIDER_POOL,
#       - delivery riders are drawn from the disjoint pool
#         (PICKUP_RIDER_POOL+1)..RIDER_POOL,
#       - within a (date, 2-hour window) a pickup rider is used at most once
#         across ALL areas, so two pickups for the same rider can never overlap,
#       - delivery trips are assigned with a per-rider cursor so a delivery
#         rider's trips never overlap each other,
#       - the pickup and delivery pools are disjoint, so a rider never holds
#         both a pickup and a delivery (no cross-kind overlap possible).
#
# Connects through the Unix socket (host=/var/run/postgresql) so no password is
# needed in Codespaces. See README "Codespaces rules".
#
# Run:  python3 05_bulk_generator.py        (called by run_p1.sh)
# =============================================================================

import random
import heapq
from datetime import date, datetime, timedelta, time
import psycopg2
from psycopg2.extras import execute_values

# ----- determinism (change the seed for a different but still-valid dataset)
random.seed(20261101)

# ----- configuration
PG_SOCKET_DIR      = "/var/run/postgresql"
DB_NAME            = "freshfold"
DB_USER            = "freshfold"

START_OFFSET_DAYS  = 730           # 2 years back from today
END_OFFSET_DAYS    = 7             # a week into the future (in-flight orders)
WINDOWS            = [time(8, 0), time(10, 0), time(12, 0),
                      time(14, 0), time(16, 0), time(18, 0)]
AREA_CAPS          = {              # mirrors the seed capacities
    "Lekki": 18, "Ikeja": 16, "Yaba": 10, "Surulere": 10, "Ajah": 8,
}
AREA_ID_BY_NAME    = {"Lekki": 1, "Ikeja": 2, "Yaba": 3, "Surulere": 4, "Ajah": 5}
NAME_BY_AREA_ID    = {v: k for k, v in AREA_ID_BY_NAME.items()}

PICKUP_RIDER_POOL   = 40           # rider IDs 1..40 do pickups only
DELIVERY_RIDER_POOL = 20           # rider IDs 41..60 do deliveries only
RIDER_POOL          = PICKUP_RIDER_POOL + DELIVERY_RIDER_POOL   # 60

TARGET_ORDERS       = 52_000       # comfortably above the 50,000 requirement

# ----- price matrix (Naira ₦) per (garment_type, service)
PRICE = {
    "shirt":    {"wash": 350,  "wash_iron": 600,  "dry_clean": 1200},
    "trouser":  {"wash": 400,  "wash_iron": 700,  "dry_clean": 1400},
    "agbada":   {"wash": 800,  "wash_iron": 1500, "dry_clean": 2500},
    "iro":      {"wash": 700,  "wash_iron": 1300, "dry_clean": 2200},
    "buba":     {"wash": 600,  "wash_iron": 1100, "dry_clean": 2000},
    "duvet":    {"wash": 2000, "wash_iron": 3500, "dry_clean": 5000},
    "bedsheet": {"wash": 1200, "wash_iron": 2200, "dry_clean": 3500},
    "suit":     {"wash": 1500, "wash_iron": 2500, "dry_clean": 6000},
    "blouse":   {"wash": 350,  "wash_iron": 600,  "dry_clean": 1200},
    "skirt":    {"wash": 350,  "wash_iron": 600,  "dry_clean": 1200},
    "ankara":   {"wash": 500,  "wash_iron": 900,  "dry_clean": 1800},
    "gown":     {"wash": 600,  "wash_iron": 1100, "dry_clean": 2200},
    "kaftan":   {"wash": 500,  "wash_iron": 1000, "dry_clean": 1800},
}
SERVICES = ["wash", "wash_iron", "dry_clean"]
GARMENTS = list(PRICE.keys())

# ----- realistic Nigerian name pools (Yoruba / Igba / Hausa / mixed)
FIRST_NAMES = [
    "Olaide", "Yetunde", "Babatunde", "Funke", "Chinedu", "Ngozi", "Emeka",
    "Chioma", "Ifeoma", "Tunde", "Kemi", "Gbenga", "Folake", "Kunle", "Tope",
    "Adaeze", "Seyi", "Bisi", "Aisha", "Ibrahim", "Fatima", "John", "Mary",
    "David", "Grace", "Samuel", "Patience", "Yusuf", "Hauza", "Adebayo",
    "Idris", "Peter", "Daniel", "Adewale", "Aminu", "Chukwuemeka", "Oluwaseun",
    "Hassan", "Vincent", "Bello", "Coker", "Lawal", "Oke", "Mbah", "Johnson",
    "Nnamdi", "Okorie", "Okon", "Effiong", "Eze", "Umeh", "Adeniran", "Suleiman",
    "Musa", "Abdullahi", "Bakare", "Olawale", "Adekunle", "Adesina", "Adeyemi",
    "Okafor", "Nwosu", "Okoro", "Obi", "Williams", "Salami", "Adeleke",
]
LAST_NAMES = [
    "Adebayo", "Okafor", "Williams", "Adeyemi", "Obi", "Eze", "Nwosu", "Okoro",
    "Salami", "Bello", "Lawal", "Adewale", "Adeleke", "Adekunle", "Adesina",
    "Makinde", "Coker", "Idris", "Johnson", "Nnamdi", "Okorie", "Musa",
    "Abdullahi", "Bakare", "Olawale", "Oke", "Mbah", "Suleiman", "Umeh",
    "Adeniran", "Effiong", "Bamidele", "Oyelowo", "Fashola", "Ogunleye",
]
VEHICLES = ["motorcycle", "motorcycle", "motorcycle", "tricycle", "tricycle", "van"]
LAGOS_ADDRESSES = {
    "Lekki":    ["Lekki Phase 1", "Admiralty Way", "Oniru Royal Estate", "Ikate Elegushi", "Ikota"],
    "Ikeja":    ["Allen Avenue", "Opebi Road", "Oba Akran Avenue", "Secretariat Road", "GRA Ikeja"],
    "Yaba":     ["Herbert Macaulay Way", "Commercial Avenue", "Sabo", "Empire Road", "Tech City"],
    "Surulere": ["Adeniran Ogunsanya", "Bode Thomas", "Ijesha Road", "Agboola Street", "Akangba"],
    "Ajah":     ["Abraham Adesanya", "Badore Road", "Sangotedo", "Idiroko Road", "Ilaje Road"],
}


def connect():
    return psycopg2.connect(host=PG_SOCKET_DIR, user=DB_USER, dbname=DB_NAME)


def ensure_riders(cur):
    """Make sure we have RIDER_POOL active riders; add more if the seed had fewer."""
    cur.execute("SELECT count(*) FROM rider WHERE active")
    n = cur.fetchone()[0]
    if n >= RIDER_POOL:
        return 0
    needed = RIDER_POOL - n
    rows = []
    for _ in range(needed):
        fn = random.choice(FIRST_NAMES)
        ln = random.choice(LAST_NAMES)
        phone = f"0802 {random.randint(3300000, 3399999)} {random.randint(1000, 9999)}"
        area_id = random.randint(1, 5)
        veh = random.choice(VEHICLES)
        rows.append((f"{fn} {ln}", phone, veh, area_id, True))
    execute_values(cur, """
        INSERT INTO rider (full_name, phone, vehicle, home_area_id, active)
        VALUES %s
    """, rows)
    return needed


def gen_slots(cur, today):
    """Create pickup slots across the 2-year span (one per area per window per day)."""
    start = today - timedelta(days=START_OFFSET_DAYS)
    end   = today + timedelta(days=END_OFFSET_DAYS)
    rows = []
    d = start
    while d <= end:
        for area_name, cap in AREA_CAPS.items():
            area_id = AREA_ID_BY_NAME[area_name]
            for ws in WINDOWS:
                we = (datetime.combine(date.min, ws) + timedelta(hours=2)).time()
                rows.append((area_id, d, ws, we, cap))
        d += timedelta(days=1)
    execute_values(cur, """
        INSERT INTO pickup_slot (area_id, slot_date, window_start, window_end, capacity)
        VALUES %s
        ON CONFLICT (area_id, slot_date, window_start) DO NOTHING
    """, rows, page_size=2000)
    return len(rows)


def load_dimension_ids(cur):
    cur.execute("SELECT customer_id, area_id FROM customer")
    customers = cur.fetchall()
    cur.execute("SELECT area_id, outlet_id FROM outlet")
    area_outlet = {a: o for a, o in cur.fetchall()}
    cur.execute("SELECT area_id, slot_date, window_start, slot_id, capacity FROM pickup_slot")
    slots = {}
    for a, sd, ws, sid, cap in cur.fetchall():
        slots[(a, sd, ws)] = (sid, cap)
    return customers, area_outlet, slots


def plan_orders(today, customers, area_outlet, slots):
    """
    Build the full order plan in Python. Returns a list of per-order dicts.
    Capacity and rider rules are respected (see module docstring).
    """
    start = today - timedelta(days=START_OFFSET_DAYS)
    end   = today + timedelta(days=END_OFFSET_DAYS)

    area_weights = {1: 5, 2: 5, 3: 3, 4: 3, 5: 2}      # area_id -> weight
    area_ids = list(area_weights.keys())

    slot_used = {k: 0 for k in slots.keys()}            # capacity tracker
    transitions = []                                     # per-order plan dicts
    order_seq = 0

    d = start
    while d <= end:
        is_future = d > today
        for ws in WINDOWS:
            weekday_factor = 1.2 if d.weekday() < 5 else 0.7
            base = random.randint(6, 22)
            n_orders = max(0, int(base * weekday_factor))
            # a pickup rider can do at most one pickup per (date, window) across all areas
            n_orders = min(n_orders, PICKUP_RIDER_POOL)
            total_cap = sum(slots[(a, d, ws)][1] for a in area_ids if (a, d, ws) in slots)
            n_orders = min(n_orders, total_cap)

            used_pickup_riders = set()
            for _ in range(n_orders):
                candidate_areas = [a for a in area_ids
                                   if (a, d, ws) in slots and slot_used[(a, d, ws)] < slots[(a, d, ws)][1]]
                if not candidate_areas:
                    break
                cw = [area_weights[a] for a in candidate_areas]
                area_id = random.choices(candidate_areas, weights=cw, k=1)[0]
                slot_id, _cap = slots[(area_id, d, ws)]
                slot_used[(area_id, d, ws)] += 1

                # customer: prefer one in the same area
                same_area_customers = [c for c in customers if c[1] == area_id]
                if same_area_customers and random.random() < 0.7:
                    cust = random.choice(same_area_customers)
                else:
                    cust = random.choice(customers)
                customer_id = cust[0]
                outlet_id = area_outlet[area_id]
                area_name = NAME_BY_AREA_ID[area_id]

                # status distribution
                if is_future:
                    final_status = "BOOKED"
                elif d > today - timedelta(days=14):
                    final_status = random.choices(
                        ["DELIVERED", "READY", "WASHING", "PICKED_UP", "CANCELLED"],
                        weights=[55, 10, 10, 15, 10])[0]
                else:
                    final_status = random.choices(
                        ["DELIVERED", "CANCELLED"], weights=[92, 8])[0]

                reaches_pickup = final_status in ("PICKED_UP", "WASHING", "READY", "DELIVERED")
                pickup_rider_id = None
                if reaches_pickup:
                    available = [r for r in range(1, PICKUP_RIDER_POOL + 1)
                                 if r not in used_pickup_riders]
                    if not available:
                        final_status = "BOOKED"
                        reaches_pickup = False
                    else:
                        pickup_rider_id = random.choice(available)
                        used_pickup_riders.add(pickup_rider_id)

                # timestamps
                slot_window_start = datetime.combine(d, ws)
                picked_up_at      = slot_window_start + timedelta(minutes=random.randint(0, 90))
                washing_started_at = picked_up_at + timedelta(minutes=random.randint(30, 120))
                ready_at          = washing_started_at + timedelta(hours=random.uniform(2, 10))
                if final_status == "DELIVERED":
                    trip_start = ready_at + timedelta(minutes=random.randint(10, 60))
                    trip_end   = trip_start + timedelta(minutes=random.randint(20, 90))
                    delivered_at = trip_end
                else:
                    trip_start = trip_end = delivered_at = None

                # items
                n_items = random.choices([1, 2, 3, 4, 5], weights=[25, 30, 25, 12, 8])[0]
                order_value = 0
                item_rows = []
                for _ in range(n_items):
                    g = random.choice(GARMENTS)
                    s = random.choice(SERVICES)
                    qty = random.choices([1, 2, 3, 4, 5], weights=[40, 30, 18, 8, 4])[0]
                    up = PRICE[g][s]
                    order_value += qty * up
                    item_rows.append((g, qty, s, up))

                # pricing model: ~15% pay-per-bag (flat ₦3500/bag), else per-item
                if random.random() < 0.15:
                    bags = random.choices([1, 2, 3], weights=[60, 30, 10])[0]
                    amount = 3500 * bags
                else:
                    amount = order_value

                pay_status = "failed" if final_status == "CANCELLED" else "paid"
                method = random.choices(["card", "transfer", "cash", "ussd"],
                                        weights=[35, 40, 15, 10])[0]
                reference = f"FF-{d.strftime('%Y%m%d')}-{ws.hour:02d}-{order_seq:06d}"
                order_seq += 1
                booked_at = slot_window_start - timedelta(hours=random.uniform(1, 24))
                addr_base = random.choice(LAGOS_ADDRESSES[area_name])
                delivery_address = f"{random.randint(1, 60)} {addr_base}, {area_name}"

                transitions.append({
                    "order_id": None,           # filled after insert
                    "final_status": final_status,
                    "customer_id": customer_id, "slot_id": slot_id,
                    "outlet_id": outlet_id, "pickup_rider_id": pickup_rider_id,
                    "booked_at": booked_at,
                    "picked_up_at": picked_up_at,
                    "washing_started_at": washing_started_at,
                    "ready_at": ready_at,
                    "delivered_at": delivered_at,
                    "trip_start": trip_start, "trip_end": trip_end,
                    "delivery_rider_id": None,  # assigned in delivery phase
                    "amount": amount, "method": method, "pay_status": pay_status,
                    "reference": reference, "items": item_rows,
                    "delivery_address": delivery_address,
                })
        d += timedelta(days=1)

    # ----- assign delivery riders with a per-rider cursor (heap) -----
    delivered = [t for t in transitions if t["final_status"] == "DELIVERED"]
    delivered.sort(key=lambda t: t["trip_start"])
    cursor_heap = [(datetime.min, r)
                   for r in range(PICKUP_RIDER_POOL + 1, RIDER_POOL + 1)]
    heapq.heapify(cursor_heap)
    for t in delivered:
        free_time, rider = heapq.heappop(cursor_heap)
        if free_time > t["trip_start"]:
            t["trip_start"] = free_time + timedelta(minutes=5)
            t["trip_end"]   = t["trip_start"] + timedelta(minutes=random.randint(20, 90))
            t["delivered_at"] = t["trip_end"]
        t["delivery_rider_id"] = rider
        heapq.heappush(cursor_heap, (t["trip_end"], rider))

    return transitions


def hop(cur, rows, to_status, cols):
    """Apply one status hop with batched UPDATE ... FROM (VALUES ...).
    `cols` is the list of timestamp column names to set alongside the status.
    The BEFORE UPDATE OF status trigger enforces the valid transition."""
    if not rows:
        return 0
    set_cols = ["status"] + cols
    set_clause = ", ".join([f"{c} = v.{c}" for c in set_cols])
    val_cols = ["order_id"] + cols + ["status"]
    val_cols_str = ", ".join(val_cols)
    template = "(" + ", ".join(["%s"] * len(val_cols)) + ")"
    sql = f"""
        UPDATE laundry_order AS o
        SET {set_clause}
        FROM (VALUES %s) AS v({val_cols_str})
        WHERE o.order_id = v.order_id
    """
    total = 0
    CHUNK = 2000
    for i in range(0, len(rows), CHUNK):
        chunk = rows[i:i + CHUNK]
        data = [(r["order_id"], *[r[c] for c in cols], to_status) for r in chunk]
        execute_values(cur, sql, data, template=template, page_size=CHUNK)
        total += len(chunk)
    return total


def main():
    print("FreshFold Laundry bulk generator")
    print(f"  target orders: {TARGET_ORDERS}+")
    today = date.today()
    conn = connect()
    conn.autocommit = False
    cur = conn.cursor()

    print("[1] ensuring dimension rows (riders)...")
    added = ensure_riders(cur)
    conn.commit()
    print(f"  riders: {added} added to reach {RIDER_POOL} active riders")

    print("[2] generating pickup slots across 2 years...")
    n_slots = gen_slots(cur, today)
    conn.commit()
    print(f"  ensured {n_slots} pickup slot rows")

    print("[3] loading dimension ids...")
    customers, area_outlet, slots = load_dimension_ids(cur)

    print("[4] planning orders in Python (respects capacity + rider rules)...")
    transitions = plan_orders(today, customers, area_outlet, slots)
    print(f"  planned {len(transitions)} orders")

    print("[5] bulk-inserting laundry_order rows (status=BOOKED)...")
    order_rows = [(t["customer_id"], t["slot_id"], t["outlet_id"], t["pickup_rider_id"],
                   None, "BOOKED", t["booked_at"], None, None, None, None,
                   t["delivery_address"]) for t in transitions]
    execute_values(cur, """
        INSERT INTO laundry_order
          (customer_id, slot_id, outlet_id, pickup_rider_id, delivery_rider_id,
           status, booked_at, picked_up_at, washing_started_at, ready_at,
           delivered_at, delivery_address)
        VALUES %s
    """, order_rows, page_size=2000)
    cur.execute("SELECT order_id FROM laundry_order ORDER BY order_id")
    order_ids = [r[0] for r in cur.fetchall()]
    assert len(order_ids) == len(transitions)
    for t, oid in zip(transitions, order_ids):
        t["order_id"] = oid
    conn.commit()
    print(f"  inserted {len(order_ids)} orders (status BOOKED)")

    print("[6] inserting order_item rows...")
    item_rows = []
    for t in transitions:
        for (g, qty, s, up) in t["items"]:
            item_rows.append((t["order_id"], g, qty, s, up))
    execute_values(cur, """
        INSERT INTO order_item (order_id, garment_type, quantity, service, unit_price)
        VALUES %s
    """, item_rows, page_size=5000)
    conn.commit()
    print(f"  inserted {len(item_rows)} order items")

    print("[7] inserting payment rows...")
    pay_rows = []
    for t in transitions:
        paid_at = t["picked_up_at"] if (t["pay_status"] == "paid" and t["picked_up_at"]) else None
        pay_rows.append((t["order_id"], t["amount"], t["method"], t["pay_status"],
                         t["reference"], paid_at))
    execute_values(cur, """
        INSERT INTO payment (order_id, amount, method, status, reference, paid_at)
        VALUES %s
    """, pay_rows, page_size=2000)
    conn.commit()
    print(f"  inserted {len(pay_rows)} payments")

    print("[8] advancing order statuses through the lifecycle (batched hops)...")
    by_status = {"PICKED_UP": [], "WASHING": [], "READY": [],
                 "DELIVERED": [], "CANCELLED": []}
    for t in transitions:
        if t["final_status"] in by_status:
            by_status[t["final_status"]].append(t)

    # PICKED_UP: BOOKED -> PICKED_UP
    hop(cur, by_status["PICKED_UP"], "PICKED_UP", ["picked_up_at"])
    # WASHING: BOOKED -> PICKED_UP -> WASHING
    hop(cur, by_status["WASHING"], "PICKED_UP", ["picked_up_at"])
    hop(cur, by_status["WASHING"], "WASHING", ["washing_started_at"])
    # READY: BOOKED -> PICKED_UP -> WASHING -> READY
    hop(cur, by_status["READY"], "PICKED_UP", ["picked_up_at"])
    hop(cur, by_status["READY"], "WASHING", ["washing_started_at"])
    hop(cur, by_status["READY"], "READY", ["ready_at"])
    # DELIVERED: BOOKED -> PICKED_UP -> WASHING -> READY -> DELIVERED
    # The final DELIVERED hop also sets delivered_at and delivery_rider_id
    # (the status transition trigger allows READY -> DELIVERED; the CHECK
    # constraints require delivered_at > picked_up_at and delivered_at >= ready_at,
    # both of which hold because delivered_at = trip_end is much later).
    hop(cur, by_status["DELIVERED"], "PICKED_UP", ["picked_up_at"])
    hop(cur, by_status["DELIVERED"], "WASHING", ["washing_started_at"])
    hop(cur, by_status["DELIVERED"], "READY", ["ready_at"])
    hop(cur, by_status["DELIVERED"], "DELIVERED", ["delivered_at", "delivery_rider_id"])
    # CANCELLED: BOOKED -> CANCELLED  (no timestamp to set)
    if by_status["CANCELLED"]:
        ids = [t["order_id"] for t in by_status["CANCELLED"]]
        CHUNK = 2000
        for i in range(0, len(ids), CHUNK):
            chunk = ids[i:i + CHUNK]
            cur.execute(
                "UPDATE laundry_order SET status = 'CANCELLED' WHERE order_id = ANY(%s)",
                (chunk,))
    conn.commit()
    print(f"  hops applied — DELIVERED={len(by_status['DELIVERED'])}, "
          f"CANCELLED={len(by_status['CANCELLED'])}, "
          f"READY={len(by_status['READY'])}, "
          f"WASHING={len(by_status['WASHING'])}, "
          f"PICKED_UP={len(by_status['PICKED_UP'])}")

    print("[9] inserting delivery rows (this fires the sync_delivery trigger)...")
    delivered = by_status["DELIVERED"]
    if delivered:
        del_rows = [(t["order_id"], t["delivery_rider_id"], t["trip_start"], t["trip_end"],
                     f"Received by {random.choice(FIRST_NAMES)}")
                    for t in delivered]
        execute_values(cur, """
            INSERT INTO delivery (order_id, rider_id, picked_up_at, delivered_at, signature)
            VALUES %s
        """, del_rows, page_size=2000)
        conn.commit()
        print(f"  inserted {len(del_rows)} delivery rows")

    print("[10] summary")
    cur.execute("SELECT count(*) FROM laundry_order");   o = cur.fetchone()[0]
    cur.execute("SELECT count(*) FROM order_item");      i = cur.fetchone()[0]
    cur.execute("SELECT count(*) FROM payment");         p = cur.fetchone()[0]
    cur.execute("SELECT count(*) FROM delivery");        dl = cur.fetchone()[0]
    cur.execute("SELECT count(*) FROM rider_assignment"); ra = cur.fetchone()[0]
    cur.execute("SELECT count(*) FROM pickup_slot");      s = cur.fetchone()[0]
    cur.execute("SELECT status, count(*) FROM laundry_order GROUP BY status ORDER BY 2 DESC")
    status_counts = cur.fetchall()
    cur.execute("""
        SELECT count(*) FROM (
          SELECT l.slot_id
          FROM laundry_order l
          JOIN pickup_slot s ON s.slot_id = l.slot_id
          WHERE l.status <> 'CANCELLED'
          GROUP BY l.slot_id, s.capacity
          HAVING count(*) > s.capacity
        ) x
    """)
    over = cur.fetchone()[0]
    print("  ------------------------------------------------")
    print(f"  orders           : {o}")
    print(f"  order items      : {i}")
    print(f"  payments         : {p}")
    print(f"  deliveries       : {dl}")
    print(f"  rider assignments: {ra}")
    print(f"  pickup slots     : {s}")
    print(f"  slots over capacity: {over}   (MUST be 0)")
    print("  status breakdown:")
    for st, c in status_counts:
        print(f"     {st:12s} {c}")
    print("  ------------------------------------------------")
    cur.close()
    conn.close()
    print("Bulk generation complete.")


if __name__ == "__main__":
    main()
