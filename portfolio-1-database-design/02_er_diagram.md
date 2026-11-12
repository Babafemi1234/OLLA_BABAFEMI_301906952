# FreshFold Laundry — ER Diagram (Mermaid)

Portfolio 1 · MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111

This ER diagram models the FreshFold Laundry case study: a customer books a pickup
slot in an area (LGA), a rider collects the clothes, an outlet washes and irons
them, the customer pays, and a rider delivers the cleaned clothes back. The rider
can never be assigned two overlapping pickups OR deliveries — that rule is enforced
by the `rider_assignment` helper entity plus an EXCLUDE constraint on a `tstzrange`.

## Entity-Relationship Diagram (Mermaid `erDiagram`)

```mermaid
erDiagram
    AREA ||--o{ OUTLET        : "has"
    AREA ||--o{ CUSTOMER      : "lives in"
    AREA ||--o{ RIDER         : "home area"
    AREA ||--o{ PICKUP_SLOT   : "covers"
    OUTLET ||--o{ LAUNDRY_ORDER : "fulfils"
    CUSTOMER ||--o{ LAUNDRY_ORDER : "places"
    PICKUP_SLOT ||--o{ LAUNDRY_ORDER : "books"
    RIDER ||--o{ LAUNDRY_ORDER : "picks up (pickup_rider)"
    RIDER ||--o{ LAUNDRY_ORDER : "delivers (delivery_rider)"
    LAUNDRY_ORDER ||--o{ ORDER_ITEM    : "contains"
    LAUNDRY_ORDER ||--|| PAYMENT       : "paid by"
    LAUNDRY_ORDER ||--o| DELIVERY      : "delivered via"
    LAUNDRY_ORDER ||--o{ RIDER_ASSIGNMENT : "generates pickup/delivery assignments"
    RIDER ||--o{ RIDER_ASSIGNMENT : "is assigned"
    DELIVERY }o--|| RIDER            : "delivered by"

    AREA {
        serial   area_id PK
        text     name        "Lekki / Ikeja / Yaba / Surulere / Ajah"
        text     lga
        text     region      "Island | Mainland"
        timestamptz created_at
    }

    OUTLET {
        serial   outlet_id PK
        text     name
        integer  area_id FK
        text     address
        text     phone
        timestamptz created_at
    }

    CUSTOMER {
        serial   customer_id PK
        text     full_name
        text     phone
        text     email
        integer  area_id FK
        text     address
        timestamptz created_at
    }

    RIDER {
        serial   rider_id PK
        text     full_name
        text     phone
        text     vehicle     "motorcycle | tricycle | van"
        integer  home_area_id FK
        boolean  active
        timestamptz created_at
    }

    PICKUP_SLOT {
        serial   slot_id PK
        integer  area_id FK
        date     slot_date
        time     window_start
        time     window_end        "window_end = window_start + 2 hours"
        integer  capacity          "capacity > 0"
        timestamptz created_at
    }

    LAUNDRY_ORDER {
        bigserial order_id PK
        integer   customer_id FK
        integer   slot_id FK
        integer   outlet_id FK
        integer   pickup_rider_id FK
        integer   delivery_rider_id FK
        text      status            "BOOKED|PICKED_UP|WASHING|READY|DELIVERED|CANCELLED"
        timestamptz booked_at
        timestamptz picked_up_at
        timestamptz washing_started_at
        timestamptz ready_at
        timestamptz delivered_at
        text      delivery_address
        timestamptz created_at
    }

    ORDER_ITEM {
        bigserial item_id PK
        bigint    order_id FK
        text      garment_type      "shirt, agbada, iro, buba, duvet..."
        integer   quantity          "quantity > 0"
        text      service           "wash | wash_iron | dry_clean"
        numeric   unit_price        "Naira (NGN)"
        numeric   line_total        "GENERATED = quantity * unit_price"
        timestamptz created_at
    }

    PAYMENT {
        bigserial payment_id PK
        bigint    order_id FK "UNIQUE — one payment per order"
        numeric   amount            "amount > 0 (Naira)"
        text      method            "card | transfer | cash | ussd"
        text      status            "paid | failed | refunded"
        text      reference         "UNIQUE"
        timestamptz paid_at
        timestamptz created_at
    }

    DELIVERY {
        bigserial delivery_id PK
        bigint    order_id FK "UNIQUE — one delivery per order"
        integer   rider_id FK
        timestamptz picked_up_at
        timestamptz delivered_at     "delivered_at > picked_up_at"
        text      signature
        timestamptz created_at
    }

    RIDER_ASSIGNMENT {
        bigserial assignment_id PK
        integer   rider_id FK
        bigint    order_id FK
        text      kind              "pickup | delivery"
        tstzrange busy_range         "EXCLUDE USING gist (rider_id =, busy_range &&)"
        timestamptz created_at
    }
```

## How the rider non-overlap rule is enforced

`rider_assignment` is a helper entity (the 9 core entities are the ones the CA
asks for; this is a supporting table for the exclusion constraint). Every time
an order is given a `pickup_rider_id`, a trigger writes a `pickup` row whose
`busy_range` is the slot's 2-hour window. Every time a delivery is recorded, a
trigger writes a `delivery` row whose `busy_range` is `[picked_up_at, delivered_at]`.
The single constraint

```sql
EXCLUDE USING gist (rider_id WITH =, busy_range WITH &&)
```

then forbids any two rows for the same rider whose `busy_range`s overlap —
pickup vs. pickup, delivery vs. delivery, or pickup vs. delivery. `btree_gist`
is what lets a scalar column (`rider_id`) be combined with a range column
(`busy_range`) inside one `EXCLUDE USING gist`.

## Cardinalities at a glance

| Relationship | Cardinality |
| --- | --- |
| area → outlet | 1 : N (an area hosts many outlets) |
| area → customer | 1 : N (a customer lives in one area) |
| area → pickup_slot | 1 : N (a slot belongs to one area) |
| area → rider | 1 : N (a rider's home area) |
| customer → laundry_order | 1 : N |
| pickup_slot → laundry_order | 1 : N (many orders per slot, up to capacity) |
| outlet → laundry_order | 1 : N |
| rider → laundry_order (pickup_rider) | 1 : N |
| rider → laundry_order (delivery_rider) | 1 : N |
| laundry_order → order_item | 1 : N |
| laundry_order → payment | 1 : 1 (UNIQUE on order_id) |
| laundry_order → delivery | 1 : 1 (UNIQUE on order_id) |
| rider → rider_assignment | 1 : N |
| laundry_order → rider_assignment | 1 : N (one pickup + one delivery) |
