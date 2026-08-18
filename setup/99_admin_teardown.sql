/*  =========================================================================== 
    99_admin_teardown.sql 
    --------------------------------------------------------------------------- 
    RUN AS: ACCOUNTADMIN 
    --------------------------------------------------------------------------- 
    Removes everything the training project created. Nothing persists beyond 
    the session. 
    
    Run the whole script to leave no trace in the account, or run section 1 
    only if you want to reset the data and demonstrate the three days again 
    without rebuilding roles and integrations. 
    =========================================================================== */
    
USE ROLE ACCOUNTADMIN;

/*  --------------------------------------------------------------------------- 
    1. RESET ONLY — drop the data, keep the account objects. 
    
    Use this to run the demo again from scratch. Drops the database, which 
    takes the raw tables, all dbt-created schemas, the snapshots and the 
    semantic view with it. 
    
    Then re-run 00 (git section only), 01, and the dbt commands. 
    --------------------------------------------------------------------------- */
    
-- DROP DATABASE IF EXISTS DBT_TRAINING_DB;


/*  --------------------------------------------------------------------------- 
    2. FULL TEARDOWN 
    --------------------------------------------------------------------------- */
    
-- The dbt project object and semantic view go with the database, but drop
-- them explicitly first so the teardown is readable and order-independent.
DROP SEMANTIC VIEW IF EXISTS DBT_TRAINING_DB.DEV_MARTS.TASTY_BYTES_SALES;
DROP DBT PROJECT IF EXISTS DBT_TRAINING_DB.DEV.TASTY_BYTES_DBT_PROJECT;
DROP DATABASE IF EXISTS DBT_TRAINING_DB;
DROP WAREHOUSE IF EXISTS DBT_TRAINING_WH;
DROP WAREHOUSE IF EXISTS DBT_TRAINING_BI_WH;
DROP ROLE IF EXISTS DBT_TRAINING_ANALYST;
DROP ROLE IF EXISTS DBT_TRAINING_TRANSFORM;
DROP ROLE IF EXISTS DBT_TRAINING_INGEST;
DROP ROLE IF EXISTS DBT_TRAINING_ADMIN;

/*  The git repository, secret and API integration are dropped with the 
    database EXCEPT the API integration, which is account-level. */
DROP API INTEGRATION IF EXISTS DBT_TRAINING_GIT_API_INTEGRATION;


/*  --------------------------------------------------------------------------- 
    3. VERIFY NOTHING REMAINS 
    --------------------------------------------------------------------------- */
    
SHOW DATABASES LIKE 'DBT_TRAINING%';
SHOW WAREHOUSES LIKE 'DBT_TRAINING%';
SHOW ROLES LIKE 'DBT_TRAINING%';
SHOW INTEGRATIONS LIKE 'DBT_TRAINING%';

-- All four should return zero rows.


/*  =========================================================================== 
    ONE LAST TEACHING POINT, IF THE SESSION IS ENDING HERE 
    --------------------------------------------------------------------------- 
    Dropping DBT_TRAINING_DB destroys DEV_SNAPSHOTS, and with it the only 
    record that customer 3 ever lived in Seattle, that truck 2 used to park at 
    Pike Place, and that customer 5 existed at all. 
    
    Every other object in this project can be rebuilt from source with one 
    command. Those two snapshot tables cannot. The source overwrote that 
    information days ago. 
    
    Worth saying as you run it: in a real warehouse, this statement is the one 
    that ends careers. Snapshots are the only thing here that is genuinely 
    irreplaceable, which is exactly why they live in their own schema, 
    why they are excluded from clean-targets, and why "just drop it and rebuild" 
    is the single instinct to unlearn from this course. 
    =========================================================================== */
