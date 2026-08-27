## DBT (Data Build Tool)

`dbt` is widely considered the most popular and dominant 
framework for building data marts and handling in-warehouse 
transformations in the modern data stack.

### Why `dbt` Dominates

  - **SQL-First Approach:**

    It allows anyone who knows SQL to write modular, reusable
    transformation logic without needing complex Spark or Java
    pipelines.

  - **Software Engineering Best Practices:**

    It brings Git version control, automated testing, continuous
    integration (CI/CD), and auto-generated data lineage
    documentation to data modeling.

  - **The Shift to ELT:**

    By moving the "T" (transformation) inside cloud data warehouses
    like Snowflake, BigQuery, and Databricks rather than external
    servers, `dbt` became the standard orchestration framework for
    final reporting layers and data marts.

 - **Massive Adoption:**

   Since the open source release in 2017, tens of thousands of data teams globally use dbt in production,
   supported by a massive community and ecosystem.


---

## Vocabulary bridge

Almost nothing in dbt is a new idea. At most there are new names for 
something you have probably  built by hand, plus the observation that 
it should live in version control.

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

Your modelling knowledge transfers 100%:

  - Grain,
  - conformed dimensions,
  - Type 1 vs Type 2,
  - degenerate dimensions,
  - fan-out traps
  - ...
  - 
All still valid and relevant, all still your job.

What dbt changes is the engineering around the modelling, not the modelling itself.

---

## Command reference

```
    dbt seed                                                load the CSV reference tables
    dbt snapshot                                            capture SCD2 history — ALWAYS FIRST
    dbt build                                               models + tests, in dependency order
    dbt build --full-refresh                                rebuild everything except snapshots
    dbt build --select stg_order_lines+                     a model and everything downstream
    dbt build --select +fct_orders                          a model and everything upstream
    dbt test --select dim_customer_history                  just the SCD2 tests
    dbt retry                                               resume after a failure
    dbt source freshness                                    is the source data current?
    dbt run-operation create_semantic_view                  build the semantic layer
    dbt docs generate --static                              docs (no `docs serve` on DPoS)
    dbt ls --select +exposure:tasty_bytes_sales_review      impact analysis
```

---

