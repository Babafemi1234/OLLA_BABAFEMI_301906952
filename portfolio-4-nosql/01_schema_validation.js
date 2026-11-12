// =============================================================================
// 01_schema_validation.js  —  Portfolio 4 MongoDB schema validation
// Portfolio 4 · MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111
// Case study: FreshFold Laundry (Lagos)
//
// Creates the `freshfold.garments` collection with a $jsonSchema validator.
// Each garment document stores the flexible, per-garment-type attributes that
// are awkward to model in strict 3NF SQL: photos, stains, fabric type, and a
// `care` sub-document whose FIELDS DEPEND ON THE GARMENT TYPE
// (e.g. agbada -> starch + iron_temp + fold_style; duvet -> machine_size +
// detergent + dry_time_mins; silk -> hand_wash_only + dry_clean_only).
//
// Run with:  mongosh mongodb://127.0.0.1:27017/freshfold 01_schema_validation.js
//   (or with auth:  mongosh mongodb://freshfold:freshfold@127.0.0.1:27017/freshfold)
// =============================================================================

const dbn = db.getName();           // expect "freshfold"
print("Running 01_schema_validation.js on database: " + dbn);

// ---------------------------------------------------------------------------
// Drop and recreate the collection with the validator (idempotent).
// ---------------------------------------------------------------------------
db.garments.drop();

db.createCollection("garments", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: [
        "order_id", "outlet_id", "outlet_name", "area",
        "garment_type", "fabric_type", "quantity", "service",
        "care", "stains", "photos", "damage_complaints", "created_at"
      ],
      properties: {
        order_id:          { bsonType: ["int","long"], description: "FK to PostgreSQL laundry_order.order_id" },
        item_id:           { bsonType: ["int","long"], description: "FK to PostgreSQL order_item.item_id (optional)" },
        outlet_id:         { bsonType: "int" },
        outlet_name:       { bsonType: "string" },
        area:              { bsonType: "string", enum: ["Lekki","Ikeja","Yaba","Surulere","Ajah"] },
        garment_type:      { bsonType: "string",
                            enum: ["shirt","trouser","agbada","iro","buba","duvet",
                                   "bedsheet","suit","blouse","skirt","ankara","gown","kaftan"] },
        fabric_type:       { bsonType: "string",
                            enum: ["cotton","polyester","linen","silk","wool",
                                   "ankara_wax","lace","damask","chiffon","denim"] },
        quantity:          { bsonType: "int", minimum: 1 },
        service:           { bsonType: "string",
                            enum: ["wash","wash_iron","dry_clean"] },
        // photos: 0..4 simulated photo URLs (the rider/outlet photographs the
        // garment before and after cleaning for damage-proof purposes).
        photos:            { bsonType: "array", items: { bsonType: "string" } },
        // stains: array of {type, location, severity, treated}
        stains: {
          bsonType: "array",
          items: {
            bsonType: "object",
            required: ["type", "severity"],
            properties: {
              type:     { bsonType: "string",
                          enum: ["grease","food","ink","blood","mud","sweat","wine",
                                 "grass","oil","perfume","makeup","rust","none"] },
              location: { bsonType: "string" },
              severity: { bsonType: "string", enum: ["light","moderate","heavy"] },
              treated:  { bsonType: "bool" }
            }
          }
        },
        // care: the per-garment-type flexible sub-document. The validator only
        // requires it to be an object; the FIELDS depend on garment_type (see
        // 02_seed_mongo.py for the per-type schema). This is exactly the
        // flexibility that strict 3NF SQL cannot give us without a wide sparse
        // table or an EAV table — the SQL-vs-NoSQL trade-off in Study Session 1.
        care: {
          bsonType: "object",
          properties: {
            iron_temp:        { bsonType: "string", enum: ["low","medium","high"] },
            starch:           { bsonType: "bool" },
            fold_style:       { bsonType: "string" },
            hand_wash_only:   { bsonType: "bool" },
            dry_clean_only:   { bsonType: "bool" },
            no_bleach:        { bsonType: "bool" },
            machine_size:     { bsonType: "string" },
            detergent:        { bsonType: "string" },
            dry_time_mins:    { bsonType: "int" },
            press_only:       { bsonType: "bool" },
            hang_dry:         { bsonType: "bool" }
          },
          additionalProperties: true
        },
        special_care_notes: { bsonType: ["string","null"] },
        // damage_complaints: array of {issue, severity, reported_at, resolved, refund_ngn}
        damage_complaints: {
          bsonType: "array",
          items: {
            bsonType: "object",
            required: ["issue", "severity"],
            properties: {
              issue:       { bsonType: "string",
                            enum: ["button_missing","colour_run","shrinkage","tear",
                                   "burn_mark","stain_persist","wrong_fold","missing_item","none"] },
              severity:    { bsonType: "string", enum: ["minor","moderate","major"] },
              reported_at: { bsonType: "date" },
              resolved:    { bsonType: "bool" },
              refund_ngn:  { bsonType: ["double","int","long"], minimum: 0 }
            }
          }
        },
        status:     { bsonType: "string", enum: ["received","washed","delivered","lost"] },
        created_at:  { bsonType: "date" }
      },
      // Allow the helper `item_id` and any future care fields. We keep
      // additionalProperties true because the whole point of the document model
      // here is per-garment-type flexibility.
      additionalProperties: true
    }
  },
  validationLevel: "moderate",     // validate inserts + updates to the validated fields
  validationAction: "error"        // reject documents that fail validation
});

// ---------------------------------------------------------------------------
// A couple of useful indexes (the garment_type IXSCAN demo lives in
// 04_index_demo.js, but we may as well create order_id now so the SQL<->Mongo
// join by order_id is fast).
// ---------------------------------------------------------------------------
db.garments.createIndex({ order_id: 1 });
db.garments.createIndex({ outlet_id: 1, area: 1 });

print("Collection `freshfold.garments` created with $jsonSchema validator.");
print("Indexes: order_id, (outlet_id, area).  garment_type index is added in 04_index_demo.js.");
