/*  =========================================================================== 
    00_admin_setup.sql 
    --------------------------------------------------------------------------- 
    RUN AS: ACCOUNTADMIN 
    WHEN: Once, BEFORE the training session. Not live in front of the team. 
    --------------------------------------------------------------------------- 
    Creates every account-level object the training project needs: warehouses, 
    database, schemas, four functional roles, grants, and the git integration. 

    Everything created here is removed by 99_teardown.sql, which leaves no 
    trace in the account. 

    --------------------------------------------------------------------------- 
    THE ROLE MODEL — worth understanding before you run this 
    --------------------------------------------------------------------------- 
    Four roles, each standing for a real actor in the pipeline:

        DBT_TRAINING_ADMIN 			the platform owner (you) 
        DBT_TRAINING_INGEST 		the SOURCE SYSTEM — may write to RAW, nothing else 
        DBT_TRAINING_TRANSFORM 		dbt — may READ raw, owns the modelled schemas 
        DBT_TRAINING_ANALYST 		BI tools and business users — marts only 
		
    The split between INGEST and TRANSFORM is the important one. It makes dbt's 
    read-only relationship to raw data structurally enforced rather than merely 
    promised: the day-2 and day-3 ingestion scripts MUST run as INGEST, because 
    TRANSFORM is physically not permitted to write to RAW. Anyone who has 
    maintained an ETL job that quietly mutated its own source will appreciate 
    why that guarantee is worth having in the grant model rather than in a 
    code review checklist. 

    ANALYST is the other one to dwell on: it cannot see DEV_STAGING or 
    DEV_INTERMEDIATE at all. The mart is the contract; the working layers are 
    private. 
    ===========================================================================*/
	
USE ROLE ACCOUNTADMIN;


/*  ---------------------------------------------------------------------------
    1. ROLES 
    --------------------------------------------------------------------------- */
	
CREATE ROLE IF NOT EXISTS DBT_TRAINING_ADMIN 
    COMMENT = 'Platform owner for the dbt training project. Owns all objects.';
	
CREATE ROLE IF NOT EXISTS DBT_TRAINING_INGEST
    COMMENT = 'Stands in for the source system. Writes to RAW only.';
	
CREATE ROLE IF NOT EXISTS DBT_TRAINING_TRANSFORM
    COMMENT = 'The role dbt runs as. Reads RAW, owns the modelled schemas.';
	
CREATE ROLE IF NOT EXISTS DBT_TRAINING_ANALYST 
	COMMENT = 'BI tools, Cortex Analyst and business users. Marts only.';
	
-- Conventional hierarchy: SYSADMIN can administer everything beneath it.
GRANT ROLE DBT_TRAINING_ADMIN TO ROLE SYSADMIN;
GRANT ROLE DBT_TRAINING_INGEST TO ROLE DBT_TRAINING_ADMIN;
GRANT ROLE DBT_TRAINING_TRANSFORM TO ROLE DBT_TRAINING_ADMIN;
GRANT ROLE DBT_TRAINING_ANALYST TO ROLE DBT_TRAINING_ADMIN;

/*  ----------------------------------------------------------------------------- 
    Grant all four to the trainer so they can switch roles freely during the
    demo. Replace <TRAINER_USER> with the presenting user's login name.
    --------------------------------------------------------------------------- */
SET trainer_user = CURRENT_USER();

GRANT ROLE DBT_TRAINING_ADMIN TO USER IDENTIFIER($trainer_user);
GRANT ROLE DBT_TRAINING_INGEST TO USER IDENTIFIER($trainer_user);
GRANT ROLE DBT_TRAINING_TRANSFORM TO USER IDENTIFIER($trainer_user);
GRANT ROLE DBT_TRAINING_ANALYST TO USER IDENTIFIER($trainer_user);


/*  --------------------------------------------------------------------------- 
    2. WAREHOUSES 
    --------------------------------------------------------------------------- 
	Two, not one. At XSMALL with a 60-second auto-suspend this costs 
	essentially nothing, and it makes the separation between transform compute 
	and consumption compute visible in query history and in the cost views. 
	"Your BI users cannot slow down your builds, and you can see exactly what 
	each one costs" is a more convincing argument when it is on screen. 
	--------------------------------------------------------------------------- */
	
CREATE WAREHOUSE IF NOT EXISTS DBT_TRAINING_WH 
    WAREHOUSE_SIZE = 'XSMALL' 
    AUTO_SUSPEND = 60 
    AUTO_RESUME = TRUE 
    INITIALLY_SUSPENDED = TRUE 
    COMMENT = 'Transform compute — dbt runs here.';
	
CREATE WAREHOUSE IF NOT EXISTS DBT_TRAINING_BI_WH 
    WAREHOUSE_SIZE = 'XSMALL' 
    AUTO_SUSPEND = 60 
    AUTO_RESUME = TRUE 
    INITIALLY_SUSPENDED = TRUE 
	COMMENT = 'Consumption compute — BI tools and Cortex Analyst.';
	
GRANT USAGE ON WAREHOUSE DBT_TRAINING_WH TO ROLE DBT_TRAINING_TRANSFORM;
GRANT USAGE ON WAREHOUSE DBT_TRAINING_WH TO ROLE DBT_TRAINING_INGEST;
GRANT USAGE ON WAREHOUSE DBT_TRAINING_WH TO ROLE DBT_TRAINING_ADMIN;
GRANT USAGE ON WAREHOUSE DBT_TRAINING_BI_WH TO ROLE DBT_TRAINING_ANALYST;
GRANT USAGE ON WAREHOUSE DBT_TRAINING_BI_WH TO ROLE DBT_TRAINING_ADMIN;

GRANT OPERATE, MONITOR ON WAREHOUSE DBT_TRAINING_WH TO ROLE DBT_TRAINING_ADMIN;
GRANT OPERATE, MONITOR ON WAREHOUSE DBT_TRAINING_BI_WH TO ROLE DBT_TRAINING_ADMIN;


/*  --------------------------------------------------------------------------- 
    3. DATABASE AND SCHEMAS 
    --------------------------------------------------------------------------- */
	
CREATE DATABASE IF NOT EXISTS DBT_TRAINING_DB 
    COMMENT = 'Tasty Bytes dbt training project.';
	
GRANT OWNERSHIP ON DATABASE DBT_TRAINING_DB TO ROLE DBT_TRAINING_ADMIN REVOKE CURRENT GRANTS;

USE ROLE DBT_TRAINING_ADMIN;
USE DATABASE DBT_TRAINING_DB;

/*  RAW is the landing zone. It belongs to the source system, not to dbt. */
CREATE SCHEMA IF NOT EXISTS RAW 
    COMMENT = 'Source data. Written by the ingestion scripts, read by dbt.';
	
/*  dbt target schemas. dbt creates DEV_STAGING, DEV_MARTS etc. beneath these.*/
CREATE SCHEMA IF NOT EXISTS DEV 
    COMMENT = 'dbt dev target.';
CREATE SCHEMA IF NOT EXISTS PROD 
    COMMENT = 'dbt prod target.';
	
/*  Home for the git repository object and the dbt project object. */
CREATE SCHEMA IF NOT EXISTS INTEGRATIONS 
    COMMENT = 'Git repository and API integration objects.';


/*  --------------------------------------------------------------------------- 
    4. GRANTS — STRUCTURAL ONLY 
    --------------------------------------------------------------------------- 
    Note what this section does NOT do: it does not grant SELECT on any mart 
    table, because no mart table exists yet. Object-level read access for the 
    ANALYST role is handled by dbt itself, declaratively, via the +grants 
    config in dbt_project.yml. See the comment there — it is one of the more 
    useful five minutes in the whole course. 
	
    The FUTURE GRANTS below are the platform-owner's equivalent, applied here 
    as a second layer. Both mechanisms solve the same problem (grants are lost 
    when dbt drops and recreates a table); they just solve it from opposite 
    ends. Future grants are the platform owner's tool. +grants is the model 
    owner's tool. Knowing when to reach for each is the actual lesson. 
    --------------------------------------------------------------------------- */
	
/*  Everyone needs to see the database exists. */
GRANT USAGE ON DATABASE DBT_TRAINING_DB TO ROLE DBT_TRAINING_INGEST;
GRANT USAGE ON DATABASE DBT_TRAINING_DB TO ROLE DBT_TRAINING_TRANSFORM;
GRANT USAGE ON DATABASE DBT_TRAINING_DB TO ROLE DBT_TRAINING_ANALYST;

/*  ---- INGEST: writes RAW, and nothing else ------------------------------- */
GRANT USAGE, CREATE TABLE, CREATE FILE FORMAT, CREATE STAGE 
    ON SCHEMA DBT_TRAINING_DB.RAW TO ROLE DBT_TRAINING_INGEST;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE 
    ON ALL TABLES IN SCHEMA DBT_TRAINING_DB.RAW TO ROLE DBT_TRAINING_INGEST;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE 
    ON FUTURE TABLES IN SCHEMA DBT_TRAINING_DB.RAW TO ROLE DBT_TRAINING_INGEST;
	
/*  ---- TRANSFORM (dbt): READS raw, OWNS the modelled schemas ----------------- 
    Read-only on RAW. This is the structural guarantee described above. */
GRANT USAGE ON SCHEMA DBT_TRAINING_DB.RAW TO ROLE DBT_TRAINING_TRANSFORM;
GRANT SELECT ON ALL TABLES IN SCHEMA DBT_TRAINING_DB.RAW TO ROLE DBT_TRAINING_TRANSFORM;
GRANT SELECT ON FUTURE TABLES IN SCHEMA DBT_TRAINING_DB.RAW TO ROLE DBT_TRAINING_TRANSFORM;

/*  dbt needs to create its own schemas (DEV_STAGING, DEV_MARTS, ...). */
GRANT CREATE SCHEMA ON DATABASE DBT_TRAINING_DB TO ROLE DBT_TRAINING_TRANSFORM;

/*  Full control of the two target schemas and everything dbt makes beneath. */
GRANT ALL PRIVILEGES ON SCHEMA DBT_TRAINING_DB.DEV TO ROLE DBT_TRAINING_TRANSFORM;
GRANT ALL PRIVILEGES ON SCHEMA DBT_TRAINING_DB.PROD TO ROLE DBT_TRAINING_TRANSFORM;

/*  The dbt project object itself lives in a schema and must be creatable. */
GRANT CREATE DBT PROJECT ON SCHEMA DBT_TRAINING_DB.DEV TO ROLE DBT_TRAINING_TRANSFORM;

/*  Semantic view creation (section 9 of the design / step 8 of the runbook). */
GRANT CREATE SEMANTIC VIEW ON SCHEMA DBT_TRAINING_DB.DEV TO ROLE DBT_TRAINING_TRANSFORM;
GRANT CREATE SEMANTIC VIEW ON SCHEMA DBT_TRAINING_DB.PROD TO ROLE DBT_TRAINING_TRANSFORM;

/*  ---- ANALYST: marts and the semantic view, nothing else ----------------- 
    Future grants at DATABASE level, then narrowed by the fact that ANALYST is
    never granted USAGE on the staging or intermediate schemas. Without schema
    USAGE, table-level SELECT is unusable — so the working layers stay private
    even though the future grant is broad. */
GRANT SELECT ON FUTURE TABLES IN DATABASE DBT_TRAINING_DB TO ROLE DBT_TRAINING_ANALYST;
GRANT SELECT ON FUTURE VIEWS IN DATABASE DBT_TRAINING_DB TO ROLE DBT_TRAINING_ANALYST;
GRANT SELECT ON FUTURE SEMANTIC VIEWS IN DATABASE DBT_TRAINING_DB TO ROLE DBT_TRAINING_ANALYST;

/*  Cortex Analyst needs this database role to answer natural-language questions. */
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE DBT_TRAINING_ANALYST;

/*  NOTE ON SCHEMA USAGE FOR ANALYST 
    The DEV_MARTS schema does not exist until dbt has run for the first time. 
    Step 6 of the runbook grants USAGE on it after the first successful build: 

        GRANT USAGE ON SCHEMA DBT_TRAINING_DB.DEV_MARTS 
            TO ROLE DBT_TRAINING_ANALYST; 

    This is deliberately left until then so the team can watch a role go from 
    "cannot see anything" to "can see exactly the mart" in one statement. */


/*  --------------------------------------------------------------------------- 
    5. GIT INTEGRATION 
    ---------------------------------------------------------------------------
    Replace the two placeholders below before running. 

    AUTHENTICATION — choose ONE: 
        (a) Public repository — simplest, but you CANNOT push from Snowsight, so 
            the branch/commit/pull-request demo beat is unavailable. 
        (b) Personal access token in a Snowflake SECRET — shown below. Avoids the 
            GitHub org-admin approval that OAuth2 usually requires. 
        (c) OAuth2 — configured through the Snowsight UI when creating the 
            workspace. Smoothest day to day, but authorises the `snowflakedb` 
            app against a GitHub account, which in a corporate org normally needs 
            org-admin approval. Confirm that early, not on the morning of the 
            demo. 
    --------------------------------------------------------------------------- */
	
USE SCHEMA DBT_TRAINING_DB.INTEGRATIONS;

/*  ---- Option (b): personal access token ------------------------------------ 
    Comment this block out entirely if you are using a public repo or OAuth2. */
CREATE SECRET IF NOT EXISTS DBT_TRAINING_GIT_SECRET 
    TYPE = password 
    USERNAME = '<YOUR_GITHUB_USERNAME>' 
    PASSWORD = '<YOUR_GITHUB_PERSONAL_ACCESS_TOKEN>' 
    COMMENT = 'GitHub PAT for the training repository.';

/* Only ACCOUNTADMIN may CREATE API INTEGRATIONS */
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE API INTEGRATION DBT_TRAINING_GIT_API_INTEGRATION 
    API_PROVIDER = git_https_api 
    API_ALLOWED_PREFIXES = ('https://github.com/<YOUR_GITHUB_ORG_OR_USER>') 
    ALLOWED_AUTHENTICATION_SECRETS = (DBT_TRAINING_GIT_SECRET) 
    ENABLED = TRUE 
    COMMENT = 'Git access for the dbt training workspace.';
	
CREATE OR REPLACE GIT REPOSITORY DBT_TRAINING_REPO 
    API_INTEGRATION = DBT_TRAINING_GIT_API_INTEGRATION 
    GIT_CREDENTIALS = DBT_TRAINING_GIT_SECRET 
    ORIGIN = 'https://github.com/<YOUR_GITHUB_ORG_OR_USER>/<YOUR_REPO_NAME>.git' 
    COMMENT = 'Source of truth for the Tasty Bytes dbt training project.';

GRANT OWNERSHIP ON SECRET DBT_TRAINING_DB.INTEGRATIONS.DBT_TRAINING_GIT_SECRET 
    TO ROLE ACCOUNTADMIN REVOKE CURRENT GRANTS;

/*  Pull the current contents of the repository into Snowflake. */
ALTER GIT REPOSITORY DBT_TRAINING_REPO FETCH;

/*  A GIT REPOSITORY is addressable as a stage. That is what lets the day-1 
    load read its CSV files straight out of the repo with COPY INTO — no file 
    upload, no client tool, no separate stage to manage. Worth demonstrating: */
LS @DBT_TRAINING_DB.INTEGRATIONS.DBT_TRAINING_REPO/branches/main/;

GRANT USAGE ON INTEGRATION DBT_TRAINING_GIT_API_INTEGRATION TO ROLE DBT_TRAINING_ADMIN;
GRANT USAGE ON SECRET DBT_TRAINING_DB.INTEGRATIONS.DBT_TRAINING_GIT_SECRET TO ROLE DBT_TRAINING_ADMIN;

GRANT USAGE ON SCHEMA DBT_TRAINING_DB.INTEGRATIONS TO ROLE DBT_TRAINING_INGEST;
GRANT USAGE ON SCHEMA DBT_TRAINING_DB.INTEGRATIONS TO ROLE DBT_TRAINING_TRANSFORM;
GRANT READ ON GIT REPOSITORY DBT_TRAINING_REPO TO ROLE DBT_TRAINING_INGEST;
GRANT READ ON GIT REPOSITORY DBT_TRAINING_REPO TO ROLE DBT_TRAINING_TRANSFORM;

USE ROLE DBT_TRAINING_ADMIN;

/*  --------------------------------------------------------------------------- 
    6. VERIFY 
    --------------------------------------------------------------------------- */
	
SHOW ROLES LIKE 'DBT_TRAINING%';
SHOW WAREHOUSES LIKE 'DBT_TRAINING%';
SHOW SCHEMAS IN DATABASE DBT_TRAINING_DB;
SHOW GRANTS ON INTEGRATION DBT_TRAINING_GIT_API_INTEGRATION;
LS @DBT_TRAINING_DB.INTEGRATIONS.DBT_TRAINING_REPO/branches/main/;

/*  Expected: 4 roles, 2 warehouses, 5 schemas (RAW, DEV, PROD, INTEGRATIONS, 
    INFORMATION_SCHEMA), and a file listing showing dbt_project.yml at the 
    repository root. If the LS returns nothing, the FETCH did not find the 
    branch — check the ORIGIN url and that the repo has at least one commit. 
    Snowflake cannot connect to a completely empty repository. */
