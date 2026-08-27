
# Tasty Bytes — dbt on Snowflake Training Project

A complete, self-contained dbt project for teaching dbt to a team that already
knows dimensional modelling and is new to dbt and Snowflake.

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

You are not alone in thinking:

>  **Snowflake is an awesome analytics platform!**



---

## What it demonstrates

  - Sources, seeds, staging, intermediate, and a star-schema mart
  - **SCD Type 2 snapshots** — both `check` and `timestamp` strategies, against 
    two sources that genuinely justify the different choices
  - **Hard-delete handling** for a right-to-erasure request
  - **Point-in-time attribution** — the same revenue question answered two ways, 
    both correct
  - **Incremental models** with merge, unique keys and a lookback window
  - **Late-arriving data** and **restatements**
  - Generic, singular and custom tests, including two that catch a broken SCD2 
    dimension
  - A four-role security model separating ingest, transform and consumption
  - A **Snowflake semantic view** for BI and Cortex Analyst
  
All with **no dbt packages** — surrogate keys, date spines and generic tests
are hand-written, so you can see what `dbt_utils` actually does.

---

## Quick start

 1. Edit the placeholders in `setup/00_admin_setup.sql` and run it as ACCOUNTADMIN
 2. Create a Snowsight Workspace from the git repo
 3. Follow the natural order of the scripts under `setup/`
 4. Deploy the dbt project object, and look around using Snowsight.

---
 
## Requirements

  - Snowflake account with `ACCOUNTADMIN` for the one-off setup
  - dbt Projects on Snowflake, dbt Core **1.11**
  - A GitHub repository and an API integration (**not** an external access 
    integration — see `packages.yml` for why that distinction matters)
  - Two XSMALL warehouses. The data is tiny by design
  
No Snowflake CLI, no local dbt install, no external access integration.
Everything runs in Snowsight.
