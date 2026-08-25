/* 
    =========================================================================== 
    01_day1_post_dbt.sql "Day 1" — business date 2026-03-01
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