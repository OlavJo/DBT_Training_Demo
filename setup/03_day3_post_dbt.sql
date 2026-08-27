/* 
    =========================================================================== 
    03_day3_post_dbt.sql "Day 3" — business date 2026-03-03
    Row counts by layer 
    --------------------------------------------------------------------------- 
    RUN AS: DBT_TRAINING_ANALYST (or ADMIN) 
    WHEN: After dbt seed, snapshot, build, following day1 initial load 
    --------------------------------------------------------------------------- 
      
    =========================================================================== 
*/

use role DBT_TRAINING_ANALYST;
use warehouse DBT_TRAINING_BI_WH;

/* 
    --------------------------------------------------------------------------- 
    Row counts 
    --------------------------------------------------------------------------- 
*/

with counts as ( 
    -- ---- source --------------------------------------------------------- 

    select 
        1 as sort_order, 
        'RAW' as layer, 
        'customer' as object_name, 
        count(*)  as row_count
    from DBT_TRAINING_DB.RAW.CUSTOMER 
    
    union all 
    
    select 
        2, 
        'RAW', 
        'truck', 
        count(*) 
    from DBT_TRAINING_DB.RAW.TRUCK 

    union all
    
    select 
        3,
        'RAW', 
        'order_header', 
        count(*) 
    from DBT_TRAINING_DB.RAW.ORDER_HEADER 
    
    union all 
    
    select 
        4, 
        'RAW', 
        'order_line', 
        count(*) 
    from DBT_TRAINING_DB.RAW.ORDER_LINE 
    
    -- ---- snapshots (history accumulates here) --------------------------- 
    
    union all 
    
    select 
        5, 
        'SNAPSHOT', 
        'snap_customer', 
        count(*) 
    from DBT_TRAINING_DB.DEV_SNAPSHOTS.SNAP_CUSTOMER 
    
    union all 
    
    select 
        6, 
        'SNAPSHOT', 
        'snap_truck', 
        count(*) 
    from DBT_TRAINING_DB.DEV_SNAPSHOTS.SNAP_TRUCK 
    
    -- ---- mart ---------------------------------------------------------- 
    
    union all 

    select 
        7, 
        'MART', 
        'dim_customer', 
        count(*) 
    from DBT_TRAINING_DB.DEV_MARTS.DIM_CUSTOMER 
    
    union all 
    
    select 
        8, 
        'MART', 
        'dim_customer_history', 
        count(*) 
    from DBT_TRAINING_DB.DEV_MARTS.DIM_CUSTOMER_HISTORY 
    
    union all 
    
    select 
        9, 
        'MART', 
        'dim_truck', 
        count(*) 
    from DBT_TRAINING_DB.DEV_MARTS.DIM_TRUCK 
    
    union all 
    
    select 
        10, 
        'MART', 
        'dim_truck_history', 
        count(*) 
    from DBT_TRAINING_DB.DEV_MARTS.DIM_TRUCK_HISTORY 

    union all 
    
    select 
        11, 
        'MART', 
        'fct_orders', 
        count(*) 
    from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDERS 
    
    union all 
    
    select 
        12, 
        'MART', 
        'fct_order_lines', 
        count(*) 
    from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDER_LINES
    
)
select 
    layer, 
    object_name, 
    row_count
from counts
order by 
    sort_order
;

/* 
    --------------------------------------------------------------------------- 
    Revenue by business date. 
    --------------------------------------------------------------------------- 
*/

select
    order_date 
    , count(*) as orders 
    , sum(gross_revenue) as gross_revenue 
    , sum(net_revenue) as net_revenue 
    , max(ingestion_lag_days) as worst_ingestion_lag_days
    
from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDERS
group by order_date
order by order_date
;


/* 
    --------------------------------------------------------------------------- 
    Aggregated truck performance
    --------------------------------------------------------------------------- 
*/

select 
    business_date,
    truck_name,
    truck_status,
    primary_location_city,

    order_count,
    line_count,
    units_sold,
    distinct_customers,
    gross_revenue,
    total_discount,
    net_revenue,
    cogs,
    gross_margin

from DBT_TRAINING_DB.DEV_MARTS.AGG_DAILY_TRUCK_PERFORMANCE
order by
    business_date,
    truck_name
;

/*
    --------------------------------------------------------------------------- 
    Historical Order line 10281 (from order 1028) was corrected.

    The proof that `merge` worked: 
    
        row count       UNCHANGED 
        revenue         UP by exactly $31.50 
    =========================================================================== 
*/

-- ---------------------------------------------------------------------------
-- 1. The headline: totals for order 1028, and the line itself.
-- ---------------------------------------------------------------------------
select 
    order_line_id 
    , order_id 
    , item_name 
    , quantity 
    , unit_price_usd 
    , line_gross_revenue 
    , line_loaded_at
    
from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDER_LINES
where order_id = 1028
order by line_number
;


-- ---------------------------------------------------------------------------
-- 2. Another perspective
-- ---------------------------------------------------------------------------
select 
    count(*) as total_line_count 
    , count(distinct order_line_id) as distinct_line_ids 
    , sum(line_gross_revenue) as total_revenue 
    , sum(
        case 
            when order_line_id = 10281 
                then line_gross_revenue 
            else 0 
        end
    ) as revenue_from_restated_line
from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDER_LINES
;


/* 
    NOTE: total_line_count and distinct_line_ids must ALWAYS be equal. 
*/


-- ---------------------------------------------------------------------------
-- 3. Did the restatement propagate to the ORDER-level fact as well?
--
-- This is the subtle one. The order HEADER for 1028 never changed — only
-- its line did. 
--
-- They agree because fct_orders watermarks on effective_loaded_at — the
-- LATER of the header's arrival and its lines'. 

-- See int_orders_with_lines.
-- ---------------------------------------------------------------------------
select 
    o.order_id 
    , o.order_date 
    , o.gross_revenue as order_level_revenue 
    , sum(l.line_gross_revenue) as sum_of_line_revenue 
    , o.gross_revenue - sum(l.line_gross_revenue) as difference 
    , o.order_loaded_at 
    , o.lines_last_loaded_at 
    , o.effective_loaded_at
    
from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDERS o
join DBT_TRAINING_DB.DEV_MARTS.FCT_ORDER_LINES l 
    on o.order_key = l.order_key
where o.order_id = 1028
group by 1,2,3,6,7,8
;

/* 
    difference must be 0.00. 
    
    Look at the three timestamps on the right after Day 3: 
    
        order_loaded_at         2026-03-02      the header never changed 
        lines_last_loaded_at    2026-03-03      the line was corrected today 
        effective_loaded_at     2026-03-03      which is what the watermark uses 
        
    That third column is the only reason this order was rebuilt. 
*/


-- ---------------------------------------------------------------------------
-- 4. Every restated line in the warehouse.
--
-- A line whose loaded_at is later than its order's loaded_at has been
-- touched after the fact. 
--
-- In production this is a useful audit query:
--   "what changed under us since we last reported?"
-- ---------------------------------------------------------------------------
select 
    order_line_id 
    , order_id 
    , order_date 
    , item_name 
    , quantity 
    , line_gross_revenue 
    , order_loaded_at 
    , line_loaded_at 
    , datediff(
        'day', 
        date(order_loaded_at), 
        date(line_loaded_at)
    ) as days_between_order_and_correction
    
from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDER_LINES
where line_loaded_at > order_loaded_at
order by line_loaded_at desc
;

/* 
    After Day 3, exactly one row: line 10281, corrected one day after the 
    order first arrived. 
*/


/*
    Changes in the history dims
*/

/*
    Customer 1 had a change of loyalty tier
    Customer 5 has been deleted
    Customer 7 appears for the first time
*/
select
    *
from DBT_TRAINING_DB.DEV_MARTS.DIM_CUSTOMER_HISTORY
order by 
    customer_id,
    version_number
;


/*  --------------------------------------------------------------------------- 
    Customer 1 was upgraded BRONZE -> GOLD. Ask "how much revenue comes from 
    GOLD members?" and there are two answers again... 
    
    Attribute by CURRENT tier and every sale customer 1 ever made retroactively 
    becomes GOLD revenue. The loyalty programme then appears to have been 
    generating GOLD revenue months before anyone was upgraded, and any analysis 
    of "what does upgrading a customer actually earn us?" is circular. 
    
    Point-in-time attribution is the only way to measure the impact.
    --------------------------------------------------------------------------- 
*/
select 
    f.customer_tier_at_order as tier_at_time_of_sale 
    , curr.loyalty_tier as tier_today 
    , count(*) as line_count 
    , sum(f.line_gross_revenue) as revenue
    
from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDER_LINES f
join DBT_TRAINING_DB.DEV_MARTS.DIM_CUSTOMER curr 
    on f.customer_key = curr.customer_key
group by 1, 2
order by 1, 2
;


/* 
    Customer 5 was deleted. Expect one version with: 
        is_current          FALSE                   she is not a current customer
        is_latest_version   TRUE                    but this is the last state we ever saw 
        valid_to            a real timestamp, NOT 9999-12-31 
        
    NOTE: valid_to here will show the WALL-CLOCK time when `dbt snapshot` ran, not 
    the load time on 2026-03-03. 
    
    That is not a defect. snap_customer borrows its timestamps from the
    source's loaded_at column (see snapshots/snap_customer.yml) — but a 
    deleted row has no loaded_at to borrow, because it no longer exists. dbt 
    falls back to the run time. 
    
    This is the honest answer for a hard delete. The only thing you 
    genuinely know is WHEN YOU NOTICED. The source did not timestamp when the 
    row was deleted. It is inferred from an absence. If the exact moment of 
    deletion matters to the business, the source has to soft-delete with a 
    timestamp — no snapshot strategy can recover information that was never 
    sent. 
    
    The two flags:
        is_current              answers "does this customer exist now?" 
        is_latest_version       answers "what is the most recent thing we know?"
    For a deleted customer those are different questions with different answers. 
*/

-- ---------------------------------------------------------------------------
-- Customer 5 reconciliation: the orders are still in the facts.
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

-- ---------------------------------------------------------------------------
-- Classifying the customers
-- ---------------------------------------------------------------------------
select 
    count(*) as all_customers 
    , count(case when not is_deleted_in_source then 1 end) as active_customers 
    , count(case when is_deleted_in_source then 1 end) as erased_customers
    
from DBT_TRAINING_DB.DEV_MARTS.DIM_CUSTOMER
;


/* 
    FINALLY, the changes to the trucks:
    
    Truck 1 has a new franchisee.
    Truck 4 is in MAINTENANCE.
    Truck 5 is new.
*/
select
    *
from DBT_TRAINING_DB.DEV_MARTS.DIM_TRUCK_HISTORY
order by 
    truck_id,
    version_number
;


