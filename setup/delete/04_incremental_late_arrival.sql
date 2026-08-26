/* 
    =========================================================================== 
    EVIDENCE 04 — The late-arriving order 
    --------------------------------------------------------------------------- 
    RUN AS: DBT_TRAINING_ANALYST 
    WHEN: After Day 2. 
    --------------------------------------------------------------------------- 
    Order 1099 was placed at 19:30 on 2026-02-28 and only reached the warehouse 
    at 06:00 on 2026-03-02, because the truck's payment terminal was offline. 
    
    These queries prove three things in order: 
        1. the order is in the fact table at all, 
        2. it is filed under the correct BUSINESS date, and 
        3. the total for 2026-02-28 CHANGED between Day 1 and Day 2. 
    =========================================================================== 
*/

use role DBT_TRAINING_ANALYST;
use warehouse DBT_TRAINING_BI_WH;


-- ---------------------------------------------------------------------------
-- 1. The order itself. Look at the gap between order_date and the load date.
-- ---------------------------------------------------------------------------
select 
    order_id 
    , order_date as business_date 
    , date(order_loaded_at) as arrived_in_warehouse 
    , ingestion_lag_days 
    , gross_revenue 
    , truck_id 
    , customer_id
    
from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDERS
where order_id = 1099
;

/* 
    Expect exactly one row, with business_date 2026-02-28, arrived 
    2026-03-02, and ingestion_lag_days = 2. 
    
    If this returns NOTHING, the incremental watermark is filtering on 
    business time instead of ingestion time — which is precisely the mistake 
    this whole exercise is built to demonstrate. See fct_orders. 
*/


-- ---------------------------------------------------------------------------
-- 2. Every order, by how late it arrived. One row stands out.
-- ---------------------------------------------------------------------------
select 
    ingestion_lag_days 
    , count(*) as order_count 
    , sum(gross_revenue) as revenue 
    , min(order_date) as earliest_business_date 
    , max(order_date) as latest_business_date
    
from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDERS
group by ingestion_lag_days
order by ingestion_lag_days
;

/* 
    Expect the overwhelming majority at lag 1 (the normal overnight batch), 
    and exactly ONE order at lag 2. 

    Worth saying out loud: in a real warehouse this distribution is a useful 
    monitoring metric in its own right. If the tail suddenly lengthens, a 
    source system is struggling, and you would rather know that from a chart 
    than from a reconciliation failure a month later. 
*/


-- ---------------------------------------------------------------------------
-- 3. THE PROOF — a "closed" day that moved.
--
-- Compare this against the figure you recorded for 2026-02-28 after Day 1.
-- It is HIGHER, by exactly the value of order 1099.
--
-- Nobody reran history. Nobody issued a backfill. The next ordinary
-- incremental run corrected a day that had already been reported, because
-- the watermark was on the right column.
-- ---------------------------------------------------------------------------
select 
    order_date 
    , count(*) as orders 
    , sum(gross_revenue) as gross_revenue 
    , sum(
        case 
            when ingestion_lag_days > 1 
                then gross_revenue 
            else 0 
        end
    ) as revenue_arriving_late 
    , count(
        case 
            when ingestion_lag_days > 1 
                then 1 
            end
        ) as orders_arriving_late
        
from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDERS
where order_date = '2026-02-28'
group by order_date
;


/* 
    --------------------------------------------------------------------------- 
    THE COUNTERFACTUAL — worth running to make the point concrete. 
    
    This is what the fact table would contain if the incremental model had 
    filtered on business time. Run it and compare the count and the revenue 
    against the real fct_orders above. 
    --------------------------------------------------------------------------- 
*/
with what_a_naive_watermark_would_have_captured as (
    -- Simulate: after Day 1, max(order_date) in the fact table was 
    -- 2026-02-28. A naive Day 2 run would take only rows strictly newer 
    -- than that by BUSINESS date. 
    select * 
    from DBT_TRAINING_DB.RAW.ORDER_HEADER 
    where 
        order_status = 'COMPLETED' 
        and ( 
            date(_loaded_at) <= '2026-03-01'        -- everything from Day 1 
            or order_ts > '2026-02-28 23:59:59'     -- plus the naive filter 
        )
)
select 
    'naive (business time)' as watermark_strategy 
    , count(*) as orders_captured
    
from what_a_naive_watermark_would_have_captured

union all

select 
    'correct (ingestion time)' 
    , count(*)
from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDERS
;

/* 
    Expect the naive strategy to be exactly ONE order short. One order, one 
    customer, $46. No error message, no failed test, no null value — just a 
    number that is quietly too small, forever. 
    
    Which is why assert_fct_orders_reconciles_to_raw exists, and why 
    reconciliation against source is the one test worth writing first. 
*/
