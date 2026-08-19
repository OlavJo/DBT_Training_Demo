/* 
    =========================================================================== 
    EVIDENCE 01 — Row counts by layer 
    --------------------------------------------------------------------------- 
    RUN AS: DBT_TRAINING_ANALYST (or ADMIN) 
    WHEN: After every dbt build, on all three days. 
    --------------------------------------------------------------------------- 
    The baseline check. Run it after each day and keep the results side by side; 
    the SHAPE of the change matters more than any individual number. 
    
    What to expect: 
    
                                    Day 1   Day 2   Day 3
        raw orders                  20      36      49 
        raw order lines             32      54      71 
        fct_orders                  19      34      47 (2 cancelled excluded) 
        fct_order_lines             31      52      69 
        dim_customer                6       6       7 (5 erased, 7 added) 
        dim_customer_history        6       7       9 
        dim_truck                   4       4       5 
        dim_truck_history           4       5       8 
        
    Two rows repay a closer look: 
    
        dim_customer_history grows FASTER than dim_customer. That gap is the 
        history being accumulated — 9 versions describing 7 customers. 
        
        Between Day 2 and Day 3, fct_order_lines rises by exactly 17 while the 
        source rises by 17. The restated line 10281 is NOT among them: it was 
        updated in place, not added. See evidence query 05. 
        
    =========================================================================== 
*/

use role DBT_TRAINING_ANALYST;
use warehouse DBT_TRAINING_BI_WH;

with counts as ( 
    -- ---- source --------------------------------------------------------- 
    select 
        1 as sort_order, 
        'RAW' as layer, 
        'order_header' as object_name, 
        count(*) as row_count 
    from DBT_TRAINING_DB.RAW.ORDER_HEADER 
    
    union all 
    
    select 
        1, 
        'RAW', 
        'order_line', 
        count(*) 
    from DBT_TRAINING_DB.RAW.ORDER_LINE 
    
    union all 
    
    select 
        1, 
        'RAW', 
        'customer', 
        count(*) 
    from DBT_TRAINING_DB.RAW.CUSTOMER 
    
    union all 
    
    select 
        1, 
        'RAW', 
        'truck', 
        count(*) 
    from DBT_TRAINING_DB.RAW.TRUCK 
    
    -- ---- snapshots (history accumulates here) --------------------------- 
    union all 
    
    select 
        2, 
        'SNAPSHOT', 
        'snap_customer', 
        count(*) 
    from DBT_TRAINING_DB.DEV_SNAPSHOTS.SNAP_CUSTOMER 
    
    union all 
    
    select 
        2, 
        'SNAPSHOT', 
        'snap_truck', 
        count(*) 
    from DBT_TRAINING_DB.DEV_SNAPSHOTS.SNAP_TRUCK 
    
    -- ---- marts ---------------------------------------------------------- 
    
    union all 
    
    select 
        3, 
        'MART', 
        'fct_orders', 
        count(*) 
    from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDERS 
    
    union all 
    
    select 
        3, 
        'MART', 
        'fct_order_lines', 
        count(*) 
    from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDER_LINES 
    
    union all 
    
    select 
        3, 
        'MART', 
        'dim_customer', 
        count(*) 
    from DBT_TRAINING_DB.DEV_MARTS.DIM_CUSTOMER 
    
    union all 
    
    select 
        3, 
        'MART', 
        'dim_customer_history', 
        count(*) 
    from DBT_TRAINING_DB.DEV_MARTS.DIM_CUSTOMER_HISTORY 
    
    union all 
    
    select 
        3, 
        'MART', 
        'dim_truck', 
        count(*) 
    from DBT_TRAINING_DB.DEV_MARTS.DIM_TRUCK 
    
    union all 
    
    select 
        3, 
        'MART', 
        'dim_truck_history', 
        count(*) 
    from DBT_TRAINING_DB.DEV_MARTS.DIM_TRUCK_HISTORY 
    
    union all 
    
    select 
        3, 
        'MART', 
        'agg_daily_truck_performance', 
        count(*) 
    from DBT_TRAINING_DB.DEV_MARTS.AGG_DAILY_TRUCK_PERFORMANCE
        
)
select 
    layer, 
    object_name, 
    row_count
from counts
order by 
    sort_order, 
    object_name;
    
/* 
    --------------------------------------------------------------------------- 
    Revenue by business date. THE headline number, and the one to watch across 
    the three days. 
    
        After Day 1:    2026-02-27 and 2026-02-28 have figures. 
        After Day 2:    2026-03-01 appears — AND 2026-02-28 HAS CHANGED, because the 
                        late-arriving order landed on it. A "closed" day moved. 
        After Day 3:    2026-03-02 appears, AND 2026-03-01 has changed, because of 
                        the restated order line. 
                        
    Two days that were already reported have been corrected without anyone 
    issuing a backfill or rerunning history. That is what "the pipeline is 
    self-correcting" actually looks like. 
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
order by order_date;
