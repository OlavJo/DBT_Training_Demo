/* 
    =========================================================================== 
    EVIDENCE 06 — Hard delete: erased from source, preserved in history 
    --------------------------------------------------------------------------- 
    RUN AS: DBT_TRAINING_ANALYST 
    WHEN: After Day 3. 
    --------------------------------------------------------------------------- 
    Customer 5, Elena Petrova, exercised her right to erasure. The source system 
    deleted her row outright. 
    
    Two things must now be true at once, and they pull against each other:
    
        (a) she disappears from current customer reporting, and 
        (b) her past orders still reconcile — those sales happened, and the 
        accounts still have to balance. 
        
    `hard_deletes: invalidate` on snap_customer makes both possible. 
    =========================================================================== 
*/

use role DBT_TRAINING_ANALYST;
use warehouse DBT_TRAINING_BI_WH;


-- ---------------------------------------------------------------------------
-- 1. Gone from the source entirely.
-- ---------------------------------------------------------------------------
select 
    count(*) as rows_in_source
    
from DBT_TRAINING_DB.RAW.CUSTOMER
where customer_id = 5
;
-- Expect 0.


-- ----------------------------------------------------------------------------- 
2. Still in dim_customer — but flagged.
--
-- This is a deliberate modelling decision, not an oversight. If the row
-- were dropped, every one of her historical orders would point at a
-- customer key that no longer exists, the relationships test on
-- fct_order_lines would fail, and anyone joining fact to dimension would
-- silently lose her revenue from their totals.
--
-- Erasure applies to the personal attributes, not to the existence of the
-- business key.
-- ---------------------------------------------------------------------------
select 
    customer_key 
    , customer_id 
    , full_name 
    , city 
    , loyalty_tier 
    , is_deleted_in_source 
    , current_version_number
    
from DBT_TRAINING_DB.DEV_MARTS.DIM_CUSTOMER
where customer_id = 5
;

/* 
    Expect one row with is_deleted_in_source = TRUE. 
    
    In a production build you would go further: null out or hash the name, 
    email and phone while keeping the key and the aggregates. That is a 
    data-protection design question rather than a dbt one, and it is left out 
    here to keep the example readable — but it is worth naming, because 
    somebody in the room will ask. 
*/


-- ---------------------------------------------------------------------------
-- 3. Her history is intact, and correctly CLOSED.
-- ---------------------------------------------------------------------------
select 
    customer_id 
    , version_number 
    , full_name 
    , city 
    , loyalty_tier 
    , valid_from 
    , valid_to 
    , is_current 
    , is_latest_version 
    , is_deleted_in_source
    
from DBT_TRAINING_DB.DEV_MARTS.DIM_CUSTOMER_HISTORY
where customer_id = 5
order by version_number
;

/* 
    Expect one version with: 
        is_current          FALSE                   she is not a current customer
        is_latest_version   TRUE                    but this is the last state we ever saw 
        valid_to            a real timestamp, NOT 9999-12-31 
        
    ONE ODDITY WORTH EXPLAINING RATHER THAN GLOSSING OVER. valid_to here will 
    show the WALL-CLOCK time you ran `dbt snapshot`, not 2026-03-03 like every 
    other timestamp in the project. 
    
    That is not a defect. snap_customer borrows its timestamps from the
    source's loaded_at column (see snapshots/snap_customer.yml) — but a 
    deleted row has no loaded_at to borrow, because it no longer exists. dbt 
    falls back to the run time. 
    
    Which is the honest answer anyway: for a hard delete, the only thing you 
    genuinely know is WHEN YOU NOTICED. The source did not tell you the row 
    was going; you inferred it from an absence. If the exact moment of 
    deletion matters to your business, the source has to soft-delete with a 
    timestamp — no snapshot strategy can recover information that was never 
    sent. 
    
    Those two flags disagreeing is the entire mechanism. is_current answers 
    "does this customer exist now?" and is_latest_version answers "what is the 
    most recent thing we know?" — and for a deleted customer those are 
    different questions with different answers. 
    
    With the default `hard_deletes: ignore`, valid_to would still be 
    9999-12-31 and she would look like an active customer indefinitely. 
*/


-- ---------------------------------------------------------------------------
-- 4. THE RECONCILIATION — her orders still tie out.
--
-- This is the query that matters to finance. She placed real orders, and
-- those orders are still in the fact table, still joinable, still
-- included in every historical total.
-- ---------------------------------------------------------------------------
select 
    f.order_date 
    , count(distinct f.order_id) as orders 
    , count(*) as lines 
    , sum(f.line_gross_revenue) as revenue 
    , max(f.customer_city_at_order) as city_at_time_of_sale
    
from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDER_LINES f
where f.customer_id = 5
group by f.order_date
order by f.order_date
;

/* 
    Expect trading on 2026-02-27, 2026-02-28 (including the late order 1099) 
    and 2026-03-01. Nothing on 2026-03-02 — she no longer exists. 
    
    Point-in-time attribution still works for her: customer_city_at_order is 
    populated from a version that has since been closed. The history outlives 
    the record. 
*/


-- ---------------------------------------------------------------------------
-- 5. And the practical question: how do I exclude her from current reporting?
--
-- Explicitly, and visibly. Not by hoping the row is missing.
-- ---------------------------------------------------------------------------
select 
    count(*) as all_customers 
    , count(case when not is_deleted_in_source then 1 end) as active_customers 
    , count(case when is_deleted_in_source then 1 end) as erased_customers
    
from DBT_TRAINING_DB.DEV_MARTS.DIM_CUSTOMER
;

/* 
    After Day 3: 7 total, 6 active, 1 erased. 
    
    The count of erased customers being VISIBLE rather than invisible is the 
    whole benefit. A deletion that silently reduces a row count is 
    indistinguishable from a pipeline failure. 
*/
