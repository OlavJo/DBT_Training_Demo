/*  ===========================================================================
    01_day1_initial_load.sql "Day 1" — business date 2026-03-01
    ---------------------------------------------------------------------------
    RUN AS: DBT_TRAINING_INGEST (the source system, NOT dbt)
    ---------------------------------------------------------------------------
    Creates the six RAW tables and loads the opening data set from the CSV
    files in setup/data/.

    Note the role. This script cannot be run by DBT_TRAINING_TRANSFORM, because
    that role has SELECT on RAW and nothing more. dbt is a reader of source
    data here, and the grant model enforces it rather than trusting it.

    ---------------------------------------------------------------------------
    ABOUT THE LOAD MECHANISM
    ---------------------------------------------------------------------------
    A GIT REPOSITORY object in Snowflake is addressable as a stage, but COPY
    INTO does not support it as a direct source. Instead, the CSV files are
    first copied to a temporary internal stage using COPY FILES, then loaded
    from there with COPY INTO. The temporary stage is dropped immediately
    after. The net effect is the same: data and code are in the same commit.

    ---------------------------------------------------------------------------
    ABOUT _LOADED_AT — the most important column in this project
    ---------------------------------------------------------------------------
    Every table carries _LOADED_AT: the moment the row arrived in the warehouse.
    This is NOT the same as ORDER_TS (when the sale happened) or UPDATED_AT
    (when the source system last changed the record).

    Keeping ingestion time separate from business time is what makes correct
    incremental processing possible. On Day 2 you will see an order whose
    business date is two days before its load date, and the difference between
    a model that watermarks on the right column and one that does not is the
    difference between complete revenue and quietly missing revenue.
    =========================================================================== */

USE ROLE DBT_TRAINING_INGEST;
USE WAREHOUSE DBT_TRAINING_WH;
USE SCHEMA DBT_TRAINING_DB.RAW;

/*  Make sure the workspace repository contents are current in Snowflake. */
ALTER GIT REPOSITORY DBT_TRAINING_DB.INTEGRATIONS.DBT_TRAINING_REPO FETCH;


/*  ---------------------------------------------------------------------------
    1. FILE FORMAT
    --------------------------------------------------------------------------- */

CREATE OR REPLACE FILE FORMAT RAW_CSV_FORMAT
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL', 'null')
    EMPTY_FIELD_AS_NULL = TRUE
    TRIM_SPACE = TRUE;


/*  ---------------------------------------------------------------------------
    2. TABLE DEFINITIONS
    ---------------------------------------------------------------------------
    Two deliberate asymmetries drive the teaching later:
      * TRUCK has a trustworthy UPDATED_AT. CUSTOMER does not.
        That is realistic — plenty of source systems maintain one and plenty
        do not — and it is what justifies running two different snapshot
        strategies side by side in the dbt project.

      * ORDER_LINE stores UNIT_PRICE_USD, the price at the moment of sale.
        MENU_ITEM stores the CURRENT price. When the menu price changes on Day 2,
        historical order lines keep the old price and the dimension
        shows the new one. Both are correct; they answer different questions.
    --------------------------------------------------------------------------- */

CREATE OR REPLACE TABLE CUSTOMER (
    CUSTOMER_ID NUMBER(38,0) NOT NULL,
    FIRST_NAME VARCHAR(100),
    LAST_NAME VARCHAR(100),
    EMAIL VARCHAR(255),
    PHONE VARCHAR(50),
    CITY VARCHAR(100),
    COUNTRY VARCHAR(10),
    POSTAL_CODE VARCHAR(20),
    LOYALTY_TIER VARCHAR(20),
    SIGN_UP_DATE DATE,
    MARKETING_OPT_IN BOOLEAN,
    _LOADED_AT TIMESTAMP_NTZ
) COMMENT = 'Customer master. No reliable update timestamp — see snap_customer.';

CREATE OR REPLACE TABLE TRUCK (
    TRUCK_ID NUMBER(38,0) NOT NULL,
    TRUCK_NAME VARCHAR(100),
    MAKE VARCHAR(50),
    MODEL VARCHAR(50),
    YEAR NUMBER(4,0),
    PRIMARY_LOCATION_ID NUMBER(38,0),
    FRANCHISEE_NAME VARCHAR(150),
    MENU_TYPE_ID NUMBER(38,0),
    TRUCK_STATUS VARCHAR(20),
    UPDATED_AT TIMESTAMP_NTZ,
    _LOADED_AT TIMESTAMP_NTZ
) COMMENT = 'Truck master. Maintains UPDATED_AT — see snap_truck.';

CREATE OR REPLACE TABLE LOCATION (
    LOCATION_ID NUMBER(38,0) NOT NULL,
    LOCATION_NAME VARCHAR(150),
    STREET VARCHAR(200),
    CITY VARCHAR(100),
    REGION VARCHAR(100),
    COUNTRY VARCHAR(10),
    LATITUDE NUMBER(9,4),
    LONGITUDE NUMBER(9,4),
    _LOADED_AT TIMESTAMP_NTZ
) COMMENT = 'Selling locations. Modelled as Type 1 — history is not kept.';

CREATE OR REPLACE TABLE MENU_ITEM (
    MENU_ITEM_ID NUMBER(38,0) NOT NULL,
    MENU_TYPE_ID NUMBER(38,0),
    ITEM_NAME VARCHAR(150),
    ITEM_CATEGORY VARCHAR(50),
    COST_OF_GOODS_USD NUMBER(10,2),
    SALE_PRICE_USD NUMBER(10,2),
    IS_HEALTHY_FLAG BOOLEAN,
    _LOADED_AT TIMESTAMP_NTZ
) COMMENT = 'Menu. SALE_PRICE_USD is the CURRENT price, not the historical one.';

CREATE OR REPLACE TABLE ORDER_HEADER (
    ORDER_ID NUMBER(38,0) NOT NULL,
    TRUCK_ID NUMBER(38,0),
    CUSTOMER_ID NUMBER(38,0),
    LOCATION_ID NUMBER(38,0),
    ORDER_TS TIMESTAMP_NTZ,
    ORDER_CHANNEL VARCHAR(20),
    ORDER_STATUS VARCHAR(20),
    ORDER_CURRENCY VARCHAR(10),
    DISCOUNT_AMOUNT NUMBER(10,2),
    _LOADED_AT TIMESTAMP_NTZ
) COMMENT = 'Order headers. ORDER_TS is business time, _LOADED_AT is arrival time.';

CREATE OR REPLACE TABLE ORDER_LINE (
    ORDER_LINE_ID NUMBER(38,0) NOT NULL,
    ORDER_ID NUMBER(38,0),
    MENU_ITEM_ID NUMBER(38,0),
    LINE_NUMBER NUMBER(5,0),
    QUANTITY NUMBER(10,0),
    UNIT_PRICE_USD NUMBER(10,2),
    _LOADED_AT TIMESTAMP_NTZ
) COMMENT = 'Order lines. UNIT_PRICE_USD is the price at time of sale.';


/*  ---------------------------------------------------------------------------
    3. LOAD FROM THE REPOSITORY
    ---------------------------------------------------------------------------
    COPY INTO does not support a Git Repository stage as a direct source.
    We copy the CSV files to a temporary internal stage first, then COPY INTO
    from there. The internal stage is dropped at the end.
    --------------------------------------------------------------------------- */

CREATE OR REPLACE TEMPORARY STAGE RAW_LOAD_STAGE
    FILE_FORMAT = RAW_CSV_FORMAT;

COPY FILES
    INTO @RAW_LOAD_STAGE
    FROM @DBT_TRAINING_DB.INTEGRATIONS.DBT_TRAINING_REPO/branches/main/setup/data/
    FILES = ('customer.csv', 'truck.csv', 'location.csv', 'menu_item.csv', 'order_header.csv', 'order_line.csv');

COPY INTO CUSTOMER
    FROM @RAW_LOAD_STAGE/customer.csv
    FILE_FORMAT = (FORMAT_NAME = RAW_CSV_FORMAT);

COPY INTO TRUCK
    FROM @RAW_LOAD_STAGE/truck.csv
    FILE_FORMAT = (FORMAT_NAME = RAW_CSV_FORMAT);

COPY INTO LOCATION
    FROM @RAW_LOAD_STAGE/location.csv
    FILE_FORMAT = (FORMAT_NAME = RAW_CSV_FORMAT);

COPY INTO MENU_ITEM
    FROM @RAW_LOAD_STAGE/menu_item.csv
    FILE_FORMAT = (FORMAT_NAME = RAW_CSV_FORMAT);

COPY INTO ORDER_HEADER
    FROM @RAW_LOAD_STAGE/order_header.csv
    FILE_FORMAT = (FORMAT_NAME = RAW_CSV_FORMAT);

COPY INTO ORDER_LINE
    FROM @RAW_LOAD_STAGE/order_line.csv
    FILE_FORMAT = (FORMAT_NAME = RAW_CSV_FORMAT);

DROP STAGE IF EXISTS RAW_LOAD_STAGE;


/*  ---------------------------------------------------------------------------
    4. VERIFY — the Day 1 baseline
    ---------------------------------------------------------------------------
    Write these numbers down, or leave the result on screen. Every later
    evidence query is a comparison against this baseline.
    --------------------------------------------------------------------------- */

SELECT
    'CUSTOMER' AS table_name,
    COUNT(*) AS row_count
FROM CUSTOMER
UNION ALL
SELECT
    'TRUCK',
    COUNT(*)
FROM TRUCK
UNION ALL
SELECT
    'LOCATION',
    COUNT(*)
FROM LOCATION
UNION ALL
SELECT
    'MENU_ITEM',
    COUNT(*)
FROM MENU_ITEM
UNION ALL
SELECT
    'ORDER_HEADER',
    COUNT(*)
FROM ORDER_HEADER
UNION ALL
SELECT
    'ORDER_LINE',
    COUNT(*)
FROM
    ORDER_LINE
ORDER BY
    table_name;

/* Expected:
CUSTOMER        6
LOCATION        5
MENU_ITEM       12
ORDER_HEADER    20 (19 completed + 1 cancelled)
ORDER_LINE      32
TRUCK           4
*/

/*  Orders by business date. Note there is nothing yet on 2026-03-01. */
SELECT
    DATE(ORDER_TS) AS order_date,
    COUNT(*) AS orders,
    MIN(_LOADED_AT) AS first_loaded_at,
    MAX(_LOADED_AT) AS last_loaded_at
FROM ORDER_HEADER
GROUP BY 1
ORDER BY 1;

/* Expected:
2026-02-27 (10 orders) and 2026-02-28 (10 orders), every row loaded at 2026-03-01 05:00.
Business time and load time are still neatly separated by a single nightly batch.
That changes tomorrow.
*/


/*
    NEXT STEPS: 

    1.  Once the initial load is completed, explore the DB Catalog > DBT_TRAINING_DB > RAW schema.
    2.  Issue the initial DBT commands:
            dbt seed
            dbt snapshot
            dbt build
    3.  Explore the DB Catalog > DBT_TRAINING_DB > (new schemas)
    4.  Explore the DBT Output, DAG and Performance tabs
    5.  Run 01_day1_post_dbt_evidence.sql
*/
