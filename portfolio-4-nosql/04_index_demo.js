// =============================================================================
// 04_index_demo.js  —  Portfolio 4 COLLSCAN -> IXSCAN demonstration
// Portfolio 4 · MIT 8103 Advanced Database Systems · Olla Babafemi · 2026/A/MIT/0111
//
// Demonstrates the difference between a COLLSCAN (collection scan, no usable
// index) and an IXSCAN (index scan) on the freshfold.garments collection, on
// the same query:
//
//     db.garments.find({ garment_type: "agbada" })
//
// BEFORE creating the index, the winning plan is a COLLSCAN over the whole
// collection. AFTER creating the index { garment_type: 1 }, the winning plan
// is an IXSCAN that touches only the matching documents.
//
// This script prints the winning plan stage, totalDocsExamined and the
// executionTimeMillis for BOTH runs. These are REAL numbers from YOUR database
// (no simulation). Capture the output and paste it into your documentation.
//
// Run with:  mongosh mongodb://127.0.0.1:27017/freshfold 04_index_demo.js
// =============================================================================

print("================================================================");
print(" Portfolio 4 — COLLSCAN -> IXSCAN on freshfold.garments");
print(" Query: { garment_type: 'agbada' }");
print("================================================================");

// Make sure no garment_type index exists for the BEFORE run.
try { db.garments.dropIndex("garment_type_1"); } catch (e) {}
print("Indexes present BEFORE: " + JSON.stringify(db.garments.getIndexes().map(i => i.name)));
print("");

function explainRun(label) {
  const ex = db.garments.find({ garment_type: "agbada" }).explain("executionStats");
  const win = ex.queryPlanner.winningPlan;
  // The stage is the top of the winning plan (COLLSCAN or IXSCAN/FETCH).
  const stage = win.stage || (win.inputStage && win.inputStage.stage) || "?";
  // drill down to find the leaf stage name for clarity
  function leafStage(plan) {
    if (!plan) return "?";
    if (plan.inputStage) return leafStage(plan.inputStage);
    return plan.stage;
  }
  const leaf = leafStage(win);
  const stats = ex.executionStats;
  print(">> " + label);
  print("   winning plan stage (root): " + stage);
  print("   leaf stage:                " + leaf);
  print("   nReturned:                 " + stats.nReturned);
  print("   totalDocsExamined:         " + stats.totalDocsExamined);
  print("   totalKeysExamined:         " + stats.totalKeysExamined);
  print("   executionTimeMillis:       " + stats.executionTimeMillis);
  print("");
  return { stage: stage, leaf: leaf, nReturned: stats.nReturned,
           totalDocsExamined: stats.totalDocsExamined,
           totalKeysExamined: stats.totalKeysExamined,
           executionTimeMillis: stats.executionTimeMillis };
}

// ---- BEFORE: COLLSCAN
print("BEFORE creating the garment_type index:");
const before = explainRun("BEFORE (no garment_type index)");

// ---- create the index
print("Creating index { garment_type: 1 } ...");
db.garments.createIndex({ garment_type: 1 });
print("Indexes present AFTER: " + JSON.stringify(db.garments.getIndexes().map(i => i.name)));
print("");

// ---- AFTER: IXSCAN
print("AFTER creating the garment_type index:");
const after = explainRun("AFTER (garment_type index)");

// ---- summary
print("================================================================");
print(" SUMMARY (real numbers from your database)");
print("   BEFORE: leaf=" + before.leaf +
      ", totalDocsExamined=" + before.totalDocsExamined +
      ", totalKeysExamined=" + before.totalKeysExamined +
      ", executionTimeMillis=" + before.executionTimeMillis);
print("   AFTER : leaf=" + after.leaf +
      ", totalDocsExamined=" + after.totalDocsExamined +
      ", totalKeysExamined=" + after.totalKeysExamined +
      ", executionTimeMillis=" + after.executionTimeMillis);
print("");
print(" Expect BEFORE.leaf = COLLSCAN (examines ~ALL documents) and");
print(" AFTER.leaf  = IXSCAN  (examines only matching documents).");
print(" Paste these real numbers into your documentation.");
print("================================================================");
