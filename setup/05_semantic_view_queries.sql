/* 
    =========================================================================== 
    05_semantic_view_queries.sql Querying the semantic view 
    --------------------------------------------------------------------------- 
    RUN AS: DBT_TRAINING_ANALYST 
    WHEN: After `dbt run-operation create_semantic_view`. 
    --------------------------------------------------------------------------- 
    Everything before this about dbt building a clean star schema. The SEMANTIC 
    VIEW is not a "view" in the usual sense. It provides METADATA characterising 
    the entire data mart, and it empowers both the BI and AI layers to generate 
    consistent and correct queries. 
    =========================================================================== 
*/

use role DBT_TRAINING_ANALYST;
use warehouse DBT_TRAINING_BI_WH;


-- ---------------------------------------------------------------------------
-- 1. What is in it?
-- ---------------------------------------------------------------------------
show semantic views in schema DBT_TRAINING_DB.DEV_MARTS;

describe semantic view DBT_TRAINING_DB.DEV_MARTS.TASTY_BYTES_SALES;


-- ---------------------------------------------------------------------------
-- 2. Total revenue and order count. No joins, no group by, no knowledge of
-- the underlying tables required.
-- ---------------------------------------------------------------------------

SELECT 
    AGG(total_revenue),
    AGG(order_count),
    AGG(avg_order_value)
FROM DBT_TRAINING_DB.DEV_MARTS.TASTY_BYTES_SALES;


-- ---------------------------------------------------------------------------
-- 3. Revenue by truck. The join to dim_truck is implied by the relationship
-- declared in the semantic view — the query does not mention it.
-- ---------------------------------------------------------------------------

SELECT 
    truck_name,
    AGG(total_revenue) AS total_revenue,
    AGG(total_units) AS total_units,
    AGG(order_count) AS order_count
FROM DBT_TRAINING_DB.DEV_MARTS.TASTY_BYTES_SALES
GROUP BY truck_name
ORDER BY total_revenue DESC;


-- ---------------------------------------------------------------------------
-- 4. Margin by menu category and day of week. Three tables joined, and the
-- query names none of them.
-- ---------------------------------------------------------------------------

SELECT 
    item_category,
    day_of_week_name,
    AGG(total_revenue),
    AGG(total_margin),
    AGG(gross_margin_pct)
FROM DBT_TRAINING_DB.DEV_MARTS.TASTY_BYTES_SALES
GROUP BY 
    item_category, 
    day_of_week_name
ORDER BY 
    item_category, 
    day_of_week_name;


-- ---------------------------------------------------------------------------
-- 5. Revenue by customer city and loyalty tier.
--
-- NOTE: this semantic view is built over dim_customer, so it uses 
-- CURRENT-STATE attribution. Customer 3's February revenue appears under Denver.
--
-- That is a deliberate choice, and the right default for a
-- business-user-facing BI layer — people asking questions in natural
-- language almost always mean "customers as they are now".
--
-- But it is a CHOICE, and it should be a conscious one. A second semantic
-- view over dim_customer_history would answer the point-in-time question
-- instead. Publishing both, clearly named, is better than publishing one
-- and letting people assume.
--
-- A semantic layer does not remove the need to understand the model underneath. 
-- It makes a modelling decision easier to consume — and easier to consume 
-- WRONGLY if nobody wrote down which question it answers.
-- ---------------------------------------------------------------------------

SELECT 
    customer_city,
    loyalty_tier,
    AGG(total_revenue),
    AGG(order_count)
FROM DBT_TRAINING_DB.DEV_MARTS.TASTY_BYTES_SALES
GROUP BY 
    customer_city, 
    loyalty_tier
ORDER BY 
    customer_city, 
    loyalty_tier;


-- ---------------------------------------------------------------------------
-- 6. Daily trend.
-- ---------------------------------------------------------------------------

SELECT 
    order_date,
    AGG(total_revenue),
    AGG(order_count),
    AGG(total_units)
FROM DBT_TRAINING_DB.DEV_MARTS.TASTY_BYTES_SALES
GROUP BY order_date
ORDER BY order_date;



/* 
    =========================================================================== 
    7. CORTEX ANALYST 
    --------------------------------------------------------------------------- 
    In Snowsight, open Cortex Analyst and point it at 
    
        DBT_TRAINING_DB.DEV_MARTS.TASTY_BYTES_SALES, 
        
    then ask in plain English: 
        
        "What was total revenue by truck last week?" 
        "Which menu category has the best margin?" 
        "Show me average order value by day of week" 
        "Who are my gold tier customers and what do they spend?" 
    
    Then — and this is the part worth doing — open the generated SQL. 
    
    It will be a `SELECT ... FROM SEMANTIC_VIEW...` statement using the 
    metrics and dimensions defined there. The synonyms declared  
    ('sales', 'AOV', 'operator', 'weekday') are what let it map casual 
    English onto the right column. 
    
    The quality of the answers is a direct function of the quality of the 
    model and the comments. A well-named, well-documented star schema 
    produces good natural-language answers.
    
    Good dimensional modelling is the thing that makes AI tooling work. 
    =========================================================================== 
*/

/*
    ===========================================================================
    AI support for using dbt in Snowflake
    ---------------------------------------------------------------------------

    Cortex Code (Claude) has read and modelled (in the neural network) almost 
    every document written about dbt, and there are plenty - dbt originated 
    in 2016. It is now is widely considered the most popular and dominant 
    framework for building data marts and handling in-warehouse transformations 
    in the modern data stack.

    This demo has been iterated and refined using AI as a pair-programming 
    partner. Knowing the framework and using AI to assist with the dbt project
    configuration makes the routine components straight-forward to build. 
    
    DBT itself is 100% standard Python / Rust code and so running 
    the framework in dev and test environments proves the correctness of the 
    configuration. No AI is involved in the actual running of the pipelines.
*/