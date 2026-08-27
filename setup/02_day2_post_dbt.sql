/* 
    =========================================================================== 
    02_day2_post_dbt.sql "Day 2" — business date 2026-03-02
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
    Order 1099 was placed at 19:30 on 2026-02-28 and only reached the warehouse 
    at 06:00 on 2026-03-02, because the truck's payment terminal was offline. 
    
    These queries prove three things: 
        1. the order is in the fact table at all, 
        2. it is filed under the correct BUSINESS date, and 
        3. the total for 2026-02-28 CHANGED between Day 1 and Day 2. 
    =========================================================================== 
*/

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
    
    See fct_orders. 
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
*/


-- ---------------------------------------------------------------------------
-- 3. THE PROOF — a "closed" day that moved.
--
-- Compare this against the figure recorded for 2026-02-28 after Day 1.
-- It is higher, by exactly the value of order 1099.
--
-- No need to rerun history or do a backfill. The next ordinary
-- incremental run corrected a day that had already been reported.
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
    The same question — "revenue by customer city" — asked two ways, over 
    identical data, returning different answers. Both are correct. 
    
    Customer 3 lived in Seattle through February and moved to Denver on 2 March. 
    
        CURRENT-STATE: her February spend counts as DENVER, because that is 
                        where she lives now. 
        POINT-IN-TIME: her February spend counts as SEATTLE, because that is 
                        where she lived then. 
                        
    Neither is a bug. They answer different business questions: 
    
        "What is my Denver customer base worth?"        -> current state 
        "What did February actually look like?"         -> point in time 
        
    The second question is the one you cannot answer without a snapshot. It 
    is also the only version that reproduces the report published in March.
    With current-state attribution, last quarter's numbers change every time 
    somebody moves house. 
    =========================================================================== 
*/

with attribution as ( 
    select 
        f.order_date 
        , f.customer_id 
        , curr.city as city_today 
        , f.customer_city_at_order as city_at_time_of_sale 
        , f.line_gross_revenue 
        
    from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDER_LINES f 
    join DBT_TRAINING_DB.DEV_MARTS.DIM_CUSTOMER curr
        on f.customer_key = curr.customer_key
        
)
select 
    city_today 
    , city_at_time_of_sale 
    , case 
        when city_today = city_at_time_of_sale 
            then '' 
        else ' <-- DISAGREES' 
    end as flag 
    , count(*) as line_count 
    , sum(line_gross_revenue) as revenue
    
from attribution
group by 1, 2, 3
order by 1, 2;


with by_current as ( 
    select 
        curr.city as city
        , sum(f.line_gross_revenue) as revenue 
    from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDER_LINES f 
    join DBT_TRAINING_DB.DEV_MARTS.DIM_CUSTOMER curr 
        on f.customer_key = curr.customer_key 
    group by 1
    
),
by_point_in_time as ( 
    select 
        f.customer_city_at_order as city
        , sum(f.line_gross_revenue) as revenue 
    from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDER_LINES f 
    group by 1
    
)
select 
    coalesce(c.city, p.city) as city 
    , c.revenue as revenue_current_state 
    , p.revenue as revenue_point_in_time 
    , round(
        coalesce(p.revenue,0) - coalesce(c.revenue,0)
        , 2
    ) as difference
    
from by_current c
full outer join 
by_point_in_time p 
    on c.city = p.city
order by 1
;


select 
    f.customer_id 
    , curr.full_name 
    , f.customer_city_at_order as city_then 
    , curr.city as city_now 
    , f.customer_tier_at_order as tier_then 
    , curr.loyalty_tier as tier_now 
    , count(*) as affected_lines
    , sum(f.line_gross_revenue) as affected_revenue
    
from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDER_LINES f
join DBT_TRAINING_DB.DEV_MARTS.DIM_CUSTOMER curr 
    on f.customer_key = curr.customer_key
where f.customer_has_changed_since
group by 1,2,3,4,5,6
order by affected_revenue desc
;




