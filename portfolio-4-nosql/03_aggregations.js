// =============================================================================
// 03_aggregations.js  —  Portfolio 4 MongoDB aggregation queries
// Portfolio 4 · MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111
// Case study: FreshFold Laundry (Lagos)
//
// Three aggregations on the `freshfold.garments` collection:
//   A. Most common stains (unwind stains -> group by type -> count -> sort)
//   B. Care requests per fabric (group by fabric_type; sum the per-garment-type
//      care flags such as starch, hand_wash_only, dry_clean_only, no_bleach)
//   C. Damage complaints per outlet (unwind damage_complaints -> group by
//      outlet -> count complaints and the most common issue)
//
// Run with:  mongosh mongodb://127.0.0.1:27017/freshfold 03_aggregations.js
// =============================================================================

print("================================================================");
print(" Portfolio 4 — MongoDB aggregations on freshfold.garments");
print("================================================================");
print("documents in collection: " + db.garments.countDocuments({}));
print("");

// ---------------------------------------------------------------------------
// A. Most common stains
// ---------------------------------------------------------------------------
print(">> A. Most common stains (top 10)");
const stainAgg = [
  // only count stains that are actually present
  { $match: { "stains.0": { $exists: true } } },
  { $unwind: "$stains" },
  { $match: { "stains.type": { $ne: "none" } } },
  { $group: {
      _id: "$stains.type",
      count:   { $sum: 1 },
      light:   { $sum: { $cond: [{ $eq: ["$stains.severity", "light"] }, 1, 0] } },
      moderate:{ $sum: { $cond: [{ $eq: ["$stains.severity", "moderate"] }, 1, 0] } },
      heavy:   { $sum: { $cond: [{ $eq: ["$stains.severity", "heavy"] }, 1, 0] } },
  } },
  { $sort: { count: -1 } },
  { $limit: 10 }
];
printjson(db.garments.aggregate(stainAgg).toArray());
print("");

// ---------------------------------------------------------------------------
// B. Care requests per fabric
//    Counts how often each care flag is requested, grouped by fabric_type.
//    Note: care flags differ per garment type (a duvet has machine_size +
//    detergent + dry_time_mins; a suit has dry_clean_only + press_only). The
//    $sum-with-$cond counts only the flags that exist for that garment.
// ---------------------------------------------------------------------------
print(">> B. Care requests per fabric");
const careAgg = [
  { $group: {
      _id: "$fabric_type",
      garments:        { $sum: 1 },
      starch_requests: { $sum: { $cond: [{ $eq: ["$care.starch", true] }, 1, 0] } },
      hand_wash_only:   { $sum: { $cond: [{ $eq: ["$care.hand_wash_only", true] }, 1, 0] } },
      dry_clean_only:   { $sum: { $cond: [{ $eq: ["$care.dry_clean_only", true] }, 1, 0] } },
      no_bleach:        { $sum: { $cond: [{ $eq: ["$care.no_bleach", true] }, 1, 0] } },
      hang_dry:         { $sum: { $cond: [{ $eq: ["$care.hang_dry", true] }, 1, 0] } },
      press_only:      { $sum: { $cond: [{ $eq: ["$care.press_only", true] }, 1, 0] } },
  } },
  { $sort: { garments: -1 } }
];
printjson(db.garments.aggregate(careAgg).toArray());
print("");

// ---------------------------------------------------------------------------
// C. Damage complaints per outlet
//    C1: complaints per outlet (count, resolved, refund)
//    C2: most common damage issue per outlet
//    C3: most common damage issue overall
// ---------------------------------------------------------------------------
print(">> C1. Damage complaints per outlet (count, resolved, refund_ngn)");
const damageAgg = [
  { $match: { "damage_complaints.0": { $exists: true } } },
  { $unwind: "$damage_complaints" },
  { $group: {
      _id: "$outlet_name",
      complaints:       { $sum: 1 },
      resolved:         { $sum: { $cond: [{ $eq: ["$damage_complaints.resolved", true] }, 1, 0] } },
      total_refund_ngn: { $sum: { $ifNull: ["$damage_complaints.refund_ngn", 0] } }
  } },
  { $sort: { complaints: -1 } }
];
printjson(db.garments.aggregate(damageAgg).toArray());
print("");

print(">> C2. Most common damage issue per outlet");
const issueByOutlet = [
  { $match: { "damage_complaints.0": { $exists: true } } },
  { $unwind: "$damage_complaints" },
  { $group: { _id: { outlet: "$outlet_name", issue: "$damage_complaints.issue" }, c: { $sum: 1 } } },
  { $sort: { c: -1 } },
  // pick the top issue per outlet
  { $group: { _id: "$_id.outlet", top_issue: { $first: "$_id.issue" }, top_count: { $first: "$c" } } },
  { $sort: { top_count: -1 } }
];
printjson(db.garments.aggregate(issueByOutlet).toArray());
print("");

print(">> C3. Most common damage issues overall");
const issueOverall = [
  { $match: { "damage_complaints.0": { $exists: true } } },
  { $unwind: "$damage_complaints" },
  { $group: { _id: "$damage_complaints.issue", count: { $sum: 1 } } },
  { $sort: { count: -1 } }
];
printjson(db.garments.aggregate(issueOverall).toArray());
print("");

print("================================================================");
print(" End of aggregations. Paste your REAL output into the LMS evidence.");
print("================================================================");
