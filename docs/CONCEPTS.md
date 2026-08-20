# Concept Map

Where each dbt concept is demonstrated in this project, and what it is called
in the world most of this team came from.

---

## Vocabulary bridge

Almost nothing in dbt is a new idea. Most of it is a new name for something
you have built by hand, plus the observation that it should live in version
control.

| dbt term | What you already call it |
|---|---|
| source | The landing/ODS tables your ETL writes to |
| staging model | Stage layer, ODS views, "the clean copy" |
| intermediate model | Work tables, temp transforms, the middle of the job |
| mart | Mart. Same word, same meaning |
| snapshot | Type 2 load, history table, SCD2 merge |
| `ref()` | The dependency your scheduler tracked by hand |
| the DAG | Your Control-M / Autosys / SSIS job dependency graph |
| incremental model | Delta load, CDC apply, "just today's rows" |
| materialization | The view-or-table decision — now config, not DDL |
| generic test | DQ check, but versioned beside the model it checks |
| singular test | That reconciliation query someone runs manually each month |
| source freshness | SLA monitoring on the feed |
| exposure | The downstream impact list nobody maintained |
| seed | Reference data, but owned by the repo instead of a spreadsheet |
| macro | A stored procedure, except it generates SQL rather than running it |

**The framing that matters:** your modelling knowledge transfers at 100%. Grain,
conformed dimensions, Type 1 vs Type 2, degenerate dimensions, fan-out traps —
all still true, all still your job. What dbt changes is the engineering around
the modelling, not the modelling itself.

---

## Where each concept lives

### Foundations

| Concept | File |
|---|---|
| Project configuration | `dbt_project.yml` |
| Connection and targets | `profiles.yml` |
| Sources and freshness | `models/staging/_staging__sources.yml` |
| Seeds — and when *not* to use one | `seeds/seeds.yml` |
| Staging discipline | `models/staging/stg_*.sql` |
| `ref()` and the DAG | Everywhere; visible in Snowsight |

### Modelling

| Concept | File |
|---|---|
| Intermediate layer, six distinct rationales | `models/intermediate/` |
| Business rule in exactly one place | `int_orders_cleaned.sql` |
| Fan-out control before a join | `int_orders_with_lines.sql` |
| Ephemeral materialization | `int_orders_with_lines.sql` |
| Star schema | `models/marts/` |
| Type 1 dimension | `dim_location.sql`, `dim_menu_item.sql` |
| Type 2 dimension | `dim_customer_history.sql`, `dim_truck_history.sql` |
| Degenerate dimensions | `fct_orders.sql` |
| Date spine without a package | `dim_date.sql` |
| Surrogate keys without a package | `macros/generate_surrogate_key.sql` |
| Hash keys vs sequences | Same file — read the second half |

### History — the part the official tutorial has none of

| Concept | File |
|---|---|
| Snapshot, `check` strategy | `snapshots/snap_customer.yml` |
| Snapshot, `timestamp` strategy | `snapshots/snap_truck.yml` |
| Why the strategies differ | Compare the two files. It is three lines |
| **What the validity windows are stamped with** | `snap_customer.yml`, the `updated_at` block |
| `hard_deletes: invalidate` | `snap_customer.yml`, day 3 change 4 |
| `dbt_valid_to_current` | Both snapshot files |
| Presenting a snapshot cleanly | `int_customer_scd.sql` |
| **Snapshots only know history from when you started** | `int_customer_scd.sql`, `effective_valid_from` |
| **Point-in-time attribution** | `int_order_lines_customer_attributed.sql` |
| Dual customer keys on the fact | `fct_order_lines.sql` |

### Incremental processing

| Concept | File |
|---|---|
| Incremental materialization | `fct_orders.sql`, `fct_order_lines.sql` |
| `merge` vs `append` | `fct_orders.sql`; proved by day 3 change 2 |
| `unique_key` | Both fact models |
| **Ingestion time vs business time** | `stg_order_headers.sql`; proved by day 2 change 2 |
| **The lookback window** | `fct_orders.sql` |
| **Parent/child watermarks** | `int_orders_with_lines.sql` |
| `on_schema_change` | Both fact models |
| When NOT to be incremental | `agg_daily_truck_performance.sql` |

### Quality

| Concept | File |
|---|---|
| Built-in generic tests | Every `_*__models.yml` |
| Custom generic tests | `tests/generic/` |
| SCD2 correctness tests | `tests/generic/scd2_*.sql` |
| Singular tests | `tests/assert_*.sql` |
| Reconciliation to source | `tests/assert_fct_orders_reconciles_to_raw.sql` |
| Parent/child integrity, both directions | `tests/assert_no_orphan_order_lines.sql` |
| Cross-model consistency | `tests/assert_order_line_revenue_ties_to_orders.sql` |
| `severity: warn` | `_marts__models.yml`, `_staging__sources.yml` |
| `store_failures` | `tests/assert_every_order_line_has_customer_attribution.sql` |
| Narrowing a test with `where` | `_marts__models.yml`, the SCD2 current test |
| `dbt build` vs `run` + `test` | `setup/04_day4_bad_data.sql` |

### Operations and governance

| Concept | File |
|---|---|
| Role separation: ingest / transform / consume | `setup/00_admin_setup.sql` |
| Grants as code | `dbt_project.yml`, the `+grants` block |
| Future grants | `setup/00_admin_setup.sql` |
| Macros and `run-operation` | `macros/create_semantic_view.sql` |
| Exposures and impact analysis | `models/marts/_marts__models.yml` |
| Semantic view for BI and AI | `macros/create_semantic_view.sql`, `analysis/08_*.sql` |
| Packages: vendoring vs EAI | `packages.yml` |

---

## The three changes that carry the course

If everything else is forgotten, these should not be.

**1. Ingestion time is not business time.**
Order 1099 was sold on 28 February and arrived on 2 March. Watermark on
business time and it is silently lost forever. → `setup/02_day2_ingestion.sql`,
`fct_orders.sql`, `analysis/04`

**2. Sources overwrite; snapshots remember.**
Customer 3 moved from Seattle to Denver, and the source destroyed the fact that
she ever lived in Seattle. Only the snapshot can still answer what February
actually looked like. → `snap_customer.yml`, `analysis/03`

**3. Corrections are updates, not inserts.**
Order line 10281 was restated from 2 to 5. `merge` updates in place; `append`
would double-count with no error and no failed test. → `setup/03_day3_ingestion.sql`,
`analysis/05`

---

## Deliberately not covered

Worth naming so nobody assumes these do not exist:

 -  **Packages (`dbt deps`)** — see `packages.yml`. Available in production two 
    different ways; omitted here so the mechanics stay visible.
 -  **Unit tests** (dbt 1.8+) — testing model *logic* against fixed inputs, 
    distinct from the data tests used throughout. The natural next topic.
 -  **Model contracts and versions** — enforcing a column schema so downstream 
    consumers cannot be broken silently.
 -  **dbt Cloud CI/CD**, **Python models**, **materialized views and dynamic 
    tables** as materializations.
    
Contracts and unit tests are the obvious part two, and would slot in without
disturbing anything here.

