#!/usr/bin/env python3
# =============================================================================
# 02_seed_mongo.py  —  Portfolio 4 MongoDB garment-document seeder
# Portfolio 4 · MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111
#
# Builds 40,000+ garment documents in MongoDB from the `order_item` rows that
# Portfolio 1 loaded into PostgreSQL. Each garment document carries the
# flexible, per-garment-type attributes that strict 3NF SQL cannot model
# cleanly: photos, stains, fabric type, and a `care` sub-document whose FIELDS
# DEPEND ON THE GARMENT TYPE.
#
# Reads from PostgreSQL (Unix socket) and writes to MongoDB (localhost:27017).
# =============================================================================

import random
from datetime import datetime, timezone, timedelta
import psycopg2
from pymongo import MongoClient, UpdateOne

random.seed(20261104)

PG_SOCKET_DIR = "/var/run/postgresql"
DB_NAME       = "freshfold"
PG_USER       = "freshfold"
MONGO_URI     = "mongodb://127.0.0.1:27017/freshfold"
# If your Codespace started mongod with auth, use:
# MONGO_URI = "mongodb://freshfold:freshfold@127.0.0.1:27017/freshfold"

TARGET_DOCS = 50_000          # comfortably above the 40,000 requirement

# fabric types realistic per garment (Nigerian wardrobe)
FABRIC_BY_GARMENT = {
    "shirt":    ["cotton", "polyester", "linen"],
    "trouser":  ["cotton", "polyester", "wool", "denim"],
    "agbada":   ["damask", "ankara_wax", "lace"],
    "iro":      ["ankara_wax", "damask", "lace"],
    "buba":     ["ankara_wax", "damask", "cotton"],
    "duvet":    ["cotton", "polyester"],
    "bedsheet": ["cotton", "polyester"],
    "suit":     ["wool", "polyester"],
    "blouse":   ["cotton", "chiffon", "silk"],
    "skirt":    ["cotton", "denim", "chiffon"],
    "ankara":   ["ankara_wax"],
    "gown":     ["silk", "chiffon", "cotton"],
    "kaftan":   ["cotton", "linen"],
}

# per-garment-type care fields (DIFFERENT FIELDS PER GARMENT TYPE)
def care_for(garment_type):
    if garment_type == "shirt":
        return {"iron_temp": random.choice(["low", "medium"]),
                "starch": random.random() < 0.5,
                "fold_style": "folded",
                "hang_dry": random.random() < 0.4}
    if garment_type == "trouser":
        return {"iron_temp": "medium",
                "starch": random.random() < 0.5,
                "fold_style": "folded",
                "press_only": False}
    if garment_type == "agbada":
        return {"iron_temp": "low",
                "starch": True,
                "fold_style": "folded",
                "dry_clean_only": random.random() < 0.5,
                "no_bleach": True}
    if garment_type in ("iro", "buba"):
        return {"iron_temp": "low",
                "starch": random.random() < 0.4,
                "fold_style": "folded",
                "hand_wash_only": random.random() < 0.3}
    if garment_type == "duvet":
        return {"machine_size": random.choice(["single", "double", "queen", "king"]),
                "detergent": "mild",
                "dry_time_mins": random.choice([60, 75, 90, 120]),
                "hang_dry": False}
    if garment_type == "bedsheet":
        return {"machine_size": random.choice(["double", "queen", "king"]),
                "detergent": "mild",
                "dry_time_mins": random.choice([45, 60, 75]),
                "hang_dry": True}
    if garment_type == "suit":
        return {"dry_clean_only": True,
                "no_bleach": True,
                "iron_temp": "low",
                "press_only": True}
    if garment_type == "blouse":
        return {"iron_temp": "low",
                "hand_wash_only": random.random() < 0.6,
                "no_bleach": True}
    if garment_type == "skirt":
        return {"iron_temp": "medium",
                "starch": False,
                "hang_dry": random.random() < 0.4}
    if garment_type == "ankara":
        return {"hand_wash_only": True,
                "no_bleach": True,
                "iron_temp": "low",
                "starch": False}
    if garment_type == "gown":
        return {"iron_temp": "low",
                "dry_clean_only": random.random() < 0.4,
                "hang_dry": True,
                "no_bleach": True}
    if garment_type == "kaftan":
        return {"iron_temp": "low",
                "starch": False,
                "hang_dry": True}
    return {"iron_temp": "low", "starch": False}

STAIN_TYPES = ["grease", "food", "ink", "blood", "mud", "sweat", "wine",
               "grass", "oil", "perfume", "makeup", "rust"]
STAIN_LOCATIONS = ["collar", "cuff", "front", "back", "sleeve", "hem", "pocket", "armpit"]
DAMAGE_ISSUES = ["button_missing", "colour_run", "shrinkage", "tear",
                 "burn_mark", "stain_persist", "wrong_fold", "missing_item"]
CARE_NOTES = [
    "Customer requested extra starch",
    "Delicate lace — handle with care",
    "Colour-fastness test before wash",
    "Do not tumble-dry",
    "Customer says stain is from palm oil",
    "Wedding outfit — priority handling",
    "Return folded, not on hanger",
]

OUTLET_NAMES = {1: "FreshFold Lekki", 2: "FreshFold Ikeja", 3: "FreshFold Yaba",
                4: "FreshFold Surulere", 5: "FreshFold Ajah"}
AREA_NAMES   = {1: "Lekki", 2: "Ikeja", 3: "Yaba", 4: "Surulere", 5: "Ajah"}


def build_doc(row):
    (item_id, order_id, garment_type, quantity, service, outlet_id, order_status, booked_at) = row
    fabric = random.choice(FABRIC_BY_GARMENT.get(garment_type, ["cotton"]))

    # stains: ~55% have at least one stain, ~45% none
    stains = []
    n_stains = 0 if random.random() < 0.45 else random.choices([1, 2, 3], weights=[60, 30, 10])[0]
    for _ in range(n_stains):
        stains.append({
            "type": random.choice(STAIN_TYPES),
            "location": random.choice(STAIN_LOCATIONS),
            "severity": random.choices(["light", "moderate", "heavy"], weights=[60, 30, 10])[0],
            "treated": random.random() < 0.85,
        })

    # photos: 0-4 simulated URLs (rider/outlet photographs before/after cleaning)
    n_photos = random.choices([0, 1, 2, 3, 4], weights=[10, 25, 35, 20, 10])[0]
    photos = [f"https://cdn.freshfold.ng/photo/{order_id}_{item_id}_{i}.jpg"
              for i in range(n_photos)]

    # damage complaints: ~7% of garments have a complaint
    damage = []
    if random.random() < 0.07:
        damage.append({
            "issue": random.choice(DAMAGE_ISSUES),
            "severity": random.choices(["minor", "moderate", "major"], weights=[60, 30, 10])[0],
            "reported_at": booked_at + timedelta(hours=random.uniform(1, 72)),
            "resolved": random.random() < 0.6,
            "refund_ngn": round(random.uniform(0, 2000), 2) if random.random() < 0.3 else 0,
        })

    # special_care_notes: ~20% of garments carry a free-text note
    notes = random.choice(CARE_NOTES) if random.random() < 0.20 else None

    # status mirrors the order's status
    if order_status == "DELIVERED":
        status = "delivered"
    elif order_status == "CANCELLED":
        status = "received"
    elif random.random() < 0.01:
        status = "lost"
    else:
        status = "washed"

    return {
        "item_id": int(item_id),
        "order_id": int(order_id),
        "outlet_id": int(outlet_id),
        "outlet_name": OUTLET_NAMES[outlet_id],
        "area": AREA_NAMES[outlet_id],
        "garment_type": garment_type,
        "fabric_type": fabric,
        "quantity": int(quantity),
        "service": service,
        "photos": photos,
        "stains": stains,
        "care": care_for(garment_type),
        "special_care_notes": notes,
        "damage_complaints": damage,
        "status": status,
        "created_at": booked_at,
    }


def main():
    print("FreshFold Laundry — MongoDB garment-document seeder")
    print(f"  target documents: {TARGET_DOCS}+")
    pg = psycopg2.connect(host=PG_SOCKET_DIR, user=PG_USER, dbname=DB_NAME)
    cur = pg.cursor()

    # sample TARGET_DOCS order_items joined to the order (for outlet/area/status/time)
    print("[1] sampling order_items from PostgreSQL ...")
    cur.execute("""
        SELECT i.item_id, i.order_id, i.garment_type, i.quantity, i.service,
               o.outlet_id, o.status, o.booked_at
        FROM order_item i
        JOIN laundry_order o ON o.order_id = i.order_id
        ORDER BY random()
        LIMIT %s
    """, (TARGET_DOCS,))
    rows = cur.fetchall()
    print(f"  sampled {len(rows)} order_items")
    cur.close()
    pg.close()

    print("[2] connecting to MongoDB ...")
    client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)
    client.admin.command("ping")
    mdb = client.freshfold
    # ensure the validator exists (run 01_schema_validation.js first)
    print("[3] inserting garment documents in batches ...")
    total = 0
    BATCH = 2000
    for i in range(0, len(rows), BATCH):
        chunk = rows[i:i + BATCH]
        docs = [build_doc(r) for r in chunk]
        res = mdb.garments.insert_many(docs, ordered=False)
        total += len(res.inserted_ids)
        print(f"  inserted {total} / {len(rows)}")
    print(f"[4] inserted {total} garment documents")

    print("[5] summary")
    n = mdb.garments.count_documents({})
    print(f"  garments.count_documents({{}}) = {n}   (MUST be >= 40000)")
    # sanity: per-garment-type `care` fields really differ
    print("  per-garment-type `care` field examples (DIFFERENT FIELDS PER GARMENT TYPE):")
    for g in ["shirt", "agbada", "duvet", "suit", "ankara"]:
        sample = mdb.garments.find_one({"garment_type": g})
        if sample:
            print(f"     {g:8s} care = {sample['care']}")
    client.close()
    print("Done.")


if __name__ == "__main__":
    main()
