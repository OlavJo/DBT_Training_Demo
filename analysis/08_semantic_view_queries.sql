/* 
    =========================================================================== 
    EVIDENCE 08 — Querying the semantic view 
    --------------------------------------------------------------------------- 
    RUN AS: DBT_TRAINING_ANALYST 
    WHEN: After `dbt run-operation create_semantic_view`. 
    --------------------------------------------------------------------------- 
    The capstone. Everything before this was building a clean star schema; 
    this is what the clean star schema buys you. 
    
    The point to make: the semantic view definition in 
    macros/create_semantic_view.sql took about eighty lines and almost no 
    thought, because every relationship it declares maps to a foreign key that 
    already exists, and every dimension it exposes is already a named, 
    documented column on a conformed dimension. 
    
    Try to write the same thing over a flat, wide "one big table" mart — the 
    kind the original Snowflake tutorial produces — and the RELATIONSHIPS 
    clause has nothing to point at. Dimensional modelling is not a legacy 
    habit to be apologised for; it is the prerequisite for the AI and BI layer 
    working at all. 
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
select *
from semantic_view( 
        DBT_TRAINING_DB.DEV_MARTS.TASTY_BYTES_SALES 
        metrics (total_revenue, order_count, avg_order_value)
    )
;


-- ---------------------------------------------------------------------------
-- 3. Revenue by truck. The join to dim_truck is implied by the relationship
-- declared in the semantic view — the query does not mention it.
-- ---------------------------------------------------------------------------
select *
from semantic_view( 
        DBT_TRAINING_DB.DEV_MARTS.TASTY_BYTES_SALES 
        metrics (total_revenue, total_units, order_count) 
        dimensions (truck_name)
    )
order by total_revenue desc
;


-- ---------------------------------------------------------------------------
-- 4. Margin by menu category and day of week. Three tables joined, and the
-- query names none of them.
-- ---------------------------------------------------------------------------
select *
from semantic_view( 
        DBT_TRAINING_DB.DEV_MARTS.TASTY_BYTES_SALES 
        metrics (total_revenue, total_margin, gross_margin_pct) 
        dimensions (item_category, day_of_week_name)
    )
order by 
    item_category, 
    day_of_week_name
;


-- ---------------------------------------------------------------------------
-- 5. Revenue by customer city and loyalty tier.
--
-- IMPORTANT AND WORTH SAYING ALOUD: this semantic view is built over
-- dim_customer, so it uses CURRENT-STATE attribution. Customer 3's
-- February revenue appears under Denver.
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
-- This is the moment to point out that a semantic layer does not remove
-- the need to understand the model underneath. It makes a modelling
-- decision easier to consume — and easier to consume WRONGLY if nobody
-- wrote down which question it answers.
-- ---------------------------------------------------------------------------
select *
from semantic_view( 
        DBT_TRAINING_DB.DEV_MARTS.TASTY_BYTES_SALES 
        metrics (total_revenue, order_count) 
        dimensions (city, loyalty_tier)
    )
order by 
    city, 
    loyalty_tier
;


-- ---------------------------------------------------------------------------
-- 6. Daily trend.
-- ---------------------------------------------------------------------------
select *
from semantic_view( 
        DBT_TRAINING_DB.DEV_MARTS.TASTY_BYTES_SALES 
        metrics (total_revenue, order_count, total_units) 
        dimensions (order_date)
    )
order by order_date
;


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
    
    It will be a `SELECT ... FROM SEMANTIC_VIEW(...)` statement using the 
    metrics and dimensions defined in the macro. The synonyms declared there 
    ('sales', 'AOV', 'operator', 'weekday') are what let it map casual English 
    onto the right column. 
    
    The honest summary for the room: the quality of the answers is a direct 
    function of the quality of the model and the comments. A well-named, 
    well-documented star schema produces good natural-language answers. A 
    sprawl of wide tables with columns called FLAG_1 and AMT_2 produces 
    confident nonsense. 
    
    Which makes the closing argument nicely circular: the dimensional 
    modelling discipline this team already has is not obsolete in the age of 
    AI tooling. It is the thing that makes the AI tooling work. 
    =========================================================================== 
*/
