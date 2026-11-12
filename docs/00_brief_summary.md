# 00 — Brief Summary & Portfolio ↔ Study-Session Map

**Student:** Olla Babafemi · **Matric:** 2026/A/MIT/0111 · **Course:** MIT 8103 Advanced Database Systems · **Case study:** FreshFold Laundry (Lagos) · **Cohort:** September 2026

---

## Part A — What the CA requires (read from `mit-8103-advanced-database-systems-ca-september-cohort-2026.pdf`)

### Assessment shape
* **Type:** Individual **practical database portfolio** — not a written essay. The deliverable is *practical evidence of technical work* supported by explanations and documentation.
* **Total marks:** 40 (Continuous Assessment).
* **Case study:** Each student picks **one** realistic organisation and uses it **consistently** across all five portfolios. Real, simulated, or realistic-scenario organisations are all acceptable. The case study must support database design, SQL queries, transactions, NoSQL modelling, and distributed/cloud discussion. FreshFold Laundry is the one chosen here.
* **Selected case study statement** (required at the start of the documentation): organisation name = FreshFold Laundry; nature of business = on-demand laundry pickup & delivery in Lagos; users of the database = customers, riders, outlet staff, finance; major data = outlets, areas/LGAs, customers, riders, pickup slots, laundry orders, order items, payments, deliveries; key operations = book a pickup slot, assign a rider, wash/iron at outlet, record payment, deliver back, track order status.

### Five portfolio components (CA section 3 & 4)

| Portfolio | Activity | Marks | Expected evidence |
| --- | --- | --- | --- |
| **P1** | Database Design and Modelling | 7 | Case study description, ER diagram, relational schema, keys, constraints, normalisation explanation. |
| **P2** | Query Processing and Optimisation | 7 | SQL queries, results, execution plans, indexing/optimisation evidence, brief performance analysis. |
| **P3** | Transactions and Concurrency | 7 | Transaction examples showing commit, rollback, isolation, concurrency issue/control, screenshots/output. |
| **P4** | NoSQL and Advanced Data Models | 7 | NoSQL model on the same case study, document/key-value/column/graph example, implementation evidence, suitability explanation. |
| **P5** | Distributed and Cloud Database Exercise | 6 | Distributed/cloud DB discussion or setup — replication, sharding, availability, consistency, deployment evidence. |
| **Final Documentation** | Portfolio documentation & technical reflection | 6 | 2–3 page summary, GitHub link, selected organisation, screenshots/evidence, individual reflection, references/AI-use declaration. |

### Page / length rules
* **Final documentation:** a **2–3 page** document submitted through the LMS, describing all five portfolio activities, the selected organisation, and a link to the GitHub repository (CA section 6).
* The portfolio itself has **no fixed page limit** — it is a repository of practical evidence. The README files in each portfolio folder are the working documentation.

### Naming rules
* The CA brief does not fix a global naming convention, but the **GitHub repository** is expected to follow the suggested structure:
  ```
  advanced-database-portfolio/
  ├── portfolio-1-database-design/
  ├── portfolio-2-query-optimisation/
  ├── portfolio-3-transactions-concurrency/
  ├── portfolio-4-nosql/
  ├── portfolio-5-distributed-cloud/
  └── README.md
  ```
  This repo follows that structure exactly.
* The final documentation PDF for this student is named **`Olla_Babafemi_2026-A-MIT-0111_Documentation.pdf`** (student name, matric, document type) so it is uniquely identifiable to the assessor. It is produced **after** the portfolios have all been run with real results.

### Submission rules (CA sections 5, 6, 8)
1. **GitHub:** create a **private** GitHub repository named `advanced-database-portfolio`, organised into the five portfolio folders above, with README files, SQL/Mongo scripts, ER diagrams, execution plans, screenshots, configuration files and test results. **Progressive commits** are expected — dumping everything on the deadline "may reduce the evidence of continuous portfolio development" (CA 8.I).
2. **LMS:** submit the 2–3 page documentation through the LMS, including the GitHub link and supporting screenshots. The **GitHub repository must be accessible to the assessor before submission** (CA section 6).
3. **Technical verification:** because the cohort is large, there is no compulsory viva. Verification relies on (i) progressive GitHub commits, (ii) clear READMEs, (iii) screenshots/outputs/execution plans/logs, (iv) a short individual technical reflection, and (v) the lecturer may select a small sample of students for brief verification if the submission is unclear, copied, inaccessible, or suspicious (CA 8.IV–VI).

### AI use and similarity rules (CA sections 7 & 11)
* **Individual work:** this is an individual assessment. General concepts may be discussed with colleagues, but the implementation, scripts, analysis, documentation and conclusions must be the student's own (CA section 7).
* **AI tools** are permitted as learning aids, but the student remains **responsible for understanding, verifying and explaining** everything submitted (CA 7).
* An **AI Use Declaration** must be included, stating: (i) the AI tool used, (ii) what it was used for, (iii) how the output was reviewed, corrected, tested or verified by the student (CA 11.I). Use of AI does **not** remove responsibility for accuracy, originality and understanding.
* **Academic integrity:** all sources, code, datasets, libraries, documentation and external resources must be properly acknowledged (CA 11).
* **Plagiarism / copying** is explicitly flagged: "students with unclear, copied, inaccessible, or suspicious submissions may be invited for an individual verification discussion" (CA 8.VI). Simply submitting screenshots or copied code without demonstrating understanding will not receive full marks (CA 10.X).

### Submission checklist (CA section 12)
1. Case study/organisation clearly stated. ✔ (FreshFold Laundry, top of repo README)
2. All five portfolios use the case study consistently. ✔
3. All five portfolios completed. ✔
4. GitHub repository properly organised. ✔
5. Practical work and supporting evidence included. ✔
6. README/documentation clearly explains the work. ✔
7. Required files submitted through the LMS. (the 2–3 page PDF — produced after running everything)
8. GitHub link works and is accessible to the assessor. `[paste your GitHub link in the repo README]`
9. All sources/datasets/libraries referenced. ✔ (per-portfolio READMEs + final documentation)
10. AI use declared. ✔ (final documentation)
11. Clear individual technical reflection + ability to explain the work if selected. ✔ (final documentation)

---

## Part B — Map of each of the 5 portfolios to the course-note study sessions

The course textbook **"Advanced Database Systems"** (Miva Open University, © 2025) has six study sessions:

| # | Study session (from the course notes' table of contents) | Topics covered |
| --- | --- | --- |
| 1 | **Review of Traditional Relational Databases and Advanced Concepts** | Database system design, stages of DB design, types of DB systems, components/characteristics of a good DB, **normalisation**, limitations of traditional DBMS, NoSQL/NewSQL intro & types (document / key-value / column / graph), NoSQL vs NewSQL |
| 2 | **Distributed Database System** | Background & architecture of distributed DB, peer-peer/client-server/federated architectures, **data fragmentation, replication, consistency models**, **CAP theorem, BASE vs ACID models**, trade-offs in distributed systems |
| 3 | **Big Data and Cloud Database Systems** | Big data, **cloud database systems**, use cases of cloud DBs, **data warehouse**, **database security** |
| 4 | **Query Optimisation in Database** | Introduction to queries, query optimisation, **query execution plans and cost estimation**, file organisation in databases |
| 5 | **Emerging Trends in Database Systems** | Database evolution, AI-powered databases (autonomous DB, Oracle AI DB), blockchain & distributed DBs, edge databases, serverless databases, **graph databases & knowledge graphs** |
| 6 | **Introduction to Data Security and Data Privacy** | Introduction to data privacy, advanced quantitative techniques, challenges of ensuring data privacy, best practices for implementing data privacy |

### Portfolio ↔ study-session mapping

| Portfolio | Primary study session(s) from the course notes | Why (concepts applied in this portfolio) |
| --- | --- | --- |
| **P1 — Database Design and Modelling** | **Study Session 1** (Review of Traditional Relational DBs & Advanced Concepts) | The ER diagram, relational schema, keys, **constraints** (PK/FK, CHECK, exclusion, triggers) and **3NF normalisation** come directly from Session 1's sections 1.1.1 (DB design stages), 1.7 (normalisation), and the components/characteristics of a good DB (1.5–1.6). |
| **P2 — Query Processing and Optimisation** | **Study Session 4** (Query Optimisation in Database) | The 6–8 analytical queries, `EXPLAIN ANALYZE` before/after indexes, and the before/after performance table map to Session 4 sections 4.1.2 (query optimisation), 4.1.3 (**query execution plans and cost estimation**), and 4.2.1 (file organisation, which underlies index access methods). |
| **P3 — Transactions and Concurrency** | **Study Session 1** (advanced concepts / ACID foundations) **+ Study Session 2** (consistency models, CAP/ACID trade-offs) | The `book_pickup()` transaction with COMMIT/ROLLBACK builds on the ACID foundations discussed in Session 1's limitations-of-traditional-DBMS section. The race condition, isolation levels, `SELECT ... FOR UPDATE`, SERIALIZABLE retries and the deadlock demo apply Session 2's consistency models and ACID material (2.2.1). |
| **P4 — NoSQL and Advanced Data Models** | **Study Session 1** (NoSQL & NewSQL, document/key-value/column/graph types) **+ Study Session 5** (graph DBs & knowledge graphs, emerging trends) | The MongoDB garment-document model with **schema validation**, per-garment-type flexible fields, aggregations and the **SQL vs NoSQL comparison** come from Session 1 sections 1.9–1.12 (NoSQL types and NoSQL vs NewSQL). The comparison and the discussion of graph-shaped relationships reference Session 5 section 5.2.1 (graph databases). |
| **P5 — Distributed and Cloud Database Exercise** | **Study Session 2** (Distributed DB) **+ Study Session 3** (Big Data & Cloud DB) **+ Study Session 6** (Data Privacy) | Monthly **partitioning** and the **streaming read replica** apply Session 2 sections 2.1.2 (architecture), 2.1.4 (**fragmentation, replication, consistency models**) and 2.2.1–2.2.2 (**CAP theorem, BASE vs ACID, trade-offs**). The **cloud architecture** keeping customer data inside Nigeria applies Session 3 (cloud database systems) **and** Session 6 (**data privacy / data security**), specifically the **Nigeria Data Protection Act 2023 (NDPA)**, which is the Nigerian law that operationalises the privacy principles taught in Session 6. The "rider apps working with poor network" discussion applies the **CAP trade-off** and eventually-consistent / async-replication material from Session 2. |

### One-line summary of the mapping
* **P1 → Session 1** (design + normalisation + constraints)
* **P2 → Session 4** (query optimisation + execution plans)
* **P3 → Sessions 1 + 2** (ACID transactions + concurrency/isolation + consistency models)
* **P4 → Sessions 1 + 5** (NoSQL document model + SQL-vs-NoSQL + graph/relational trade-offs)
* **P5 → Sessions 2 + 3 + 6** (distributed DB + replication + CAP + cloud + Nigerian data-privacy law)

---

## How to read this folder

* `00_brief_summary.md` (this file) is the orientation document — read it first.
* Each `portfolio-N-*/README.md` explains the exact Codespaces commands, what to screenshot, the `git commit` command, a plain-English description of what the portfolio demonstrates, and the study session it maps to.
* Run `setup.sh` once, then each `run_pN.sh` in order.
* The final 2–3 page documentation PDF is written **after** everything has been run and the real `[paste real output here]` placeholders have been replaced with captured results.
