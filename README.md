
# Tasty Bytes — dbt on Snowflake Training Project

A complete, self-contained dbt project for teaching dbt to a team that already
knows dimensional modelling and is new to both dbt and Snowflake.

It exists because every public dbt example builds a project **once** against
static data and stops. That structure cannot demonstrate the things that
matter most in production: why snapshots exist, why incremental models need a
lookback window, why `merge` beats `append`, and what "the mart updated
correctly" looks like as evidence.

This project simulates **three days of ingestion**, with each day's changes
engineered to break a naive implementation.

## Acknowledgement and Shout-Out

This teaching project is inspired by Snowflake's own documentation available here:

[Tutorial: Get started with dbt Projects on Snowflake](
https://docs.snowflake.com/en/user-guide/tutorials/dbt-projects-on-snowflake-getting-started-tutorial)

Remember: **Snowflake is awesome!**



---

## What it demonstrates

  - Sources, seeds, staging, **intermediate**, and a star-schema mart
  - **SCD Type 2 snapshots** — both `check` and `timestamp` strategies, against 
    two sources that genuinely justify the different choices
  - **Hard-delete handling** for a right-to-erasure request
  - **Point-in-time attribution** — the same revenue question answered two ways, 
    both correct
  - **Incremental models** with merge, unique keys and a lookback window
  - **Late-arriving data** and **restatements**, and what each one breaks
  - Generic, singular and custom tests, including two that catch a broken SCD2 
    dimension
  - A four-role security model separating ingest, transform and consumption
  - A **Snowflake semantic view** for BI and Cortex Analyst
  
All with **no dbt packages** — surrogate keys, date spines and generic tests
are hand-written, so you can see what `dbt_utils` actually does.

---

## Start here
| Document | For |
|---|---|
| **[docs/RUNBOOK.md](docs/RUNBOOK.md)** | The trainer. Session plans, timings, what to say |
| [docs/CONCEPTS.md](docs/CONCEPTS.md) | Vocabulary bridge and concept-to-file map |
| [docs/DESIGN.md](docs/DESIGN.md) | Why the project is built this way |

---

## Layout

```
setup/ 								Snowflake setup and the three days of ingestion 
    00_admin_setup.sql 				ACCOUNTADMIN — roles, warehouses, git integration 
    01_day1_initial_load.sql 		INGEST — raw tables + CSV load 
    02_day2_ingestion.sql 			INGEST — late order, customer moves, truck relocates 
    03_day3_ingestion.sql 			INGEST — restatement, erasure, tier upgrade 
    04_day4_bad_data.sql 			INGEST — optional failure drill 
    99_teardown.sql 				ACCOUNTADMIN — leaves no trace 
	data/ 							Day-1 CSVs, loaded from the git repository stage
	
seeds/ 								Reference data owned by this repo
models/
    staging/ 						One view per source. No joins, no business logic 
	intermediate/ 					Six models, six distinct rationales 
	marts/ 							Star schema: 7 dimensions, 2 facts, 1 aggregate
	snapshots/ 						SCD2 history. The only thing here that cannot be rebuilt
	macros/ 						Surrogate keys, semantic view
	tests/ 							Singular tests; generic/ holds the reusable ones
	analysis/ 						Evidence queries — run these after each day
```

---

## The three days

| Day | What changes | What it forces |
|---|---|---|
| 1 | Initial load: 6 customers, 4 trucks, 20 orders | Baseline |
| 2 | New orders • **late-arriving order** • customer relocates • truck moves • location renamed • menu price rises | Watermark on ingestion time; SCD2 both strategies; Type 1 contrast |
| 3 | New orders • **restated line** • tier upgrade • **customer erased** • truck to maintenance • new customer and truck | `merge` not `append`; hard-delete handling |

After each day: `dbt snapshot` → `dbt build` → the evidence queries.

**`dbt snapshot` always runs first.** Snapshot late and the change is captured
a run behind, and that day's point-in-time attribution is wrong.

---

## Quick start

Full instructions are in [docs/RUNBOOK.md](docs/RUNBOOK.md). In brief:

 1. Push this repo to GitHub (needs at least one commit)
 2. Edit the placeholders in `setup/00_admin_setup.sql` and run it as ACCOUNTADMIN
 3. Create a Snowsight Workspace from the git repo
 4. Deploy the dbt project object
 5. Run `setup/01_day1_initial_load.sql` as `DBT_TRAINING_INGEST`
 6. In the Workspace:

```
dbt seed
dbt snapshot
dbt build
```

 7. Run `analysis/01_row_counts_by_layer.sql` and record the baseline
 8. Repeat for days 2 and 3
 
---
 
## Requirements

  - Snowflake account with `ACCOUNTADMIN` for the one-off setup
  - dbt Projects on Snowflake, dbt Core **1.11**
  - A GitHub repository and an API integration (**not** an external access 
    integration — see `packages.yml` for why that distinction matters)
  - Two XSMALL warehouses. The data is tiny by design
  
No Snowflake CLI, no local dbt install, no external access integration.
Everything runs in Snowsight.
