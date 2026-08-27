/* 
    =========================================================================== 
    EVIDENCE 07 — Aggregate drift: why some models are rebuilt in full 
    --------------------------------------------------------------------------- 
    RUN AS: DBT_TRAINING_ANALYST 
    WHEN: After each day. The comparison ACROSS days is the point. 
    --------------------------------------------------------------------------- 
    agg_daily_truck_performance is materialised as a TABLE and rebuilt from 
    scratch on every run, while the two facts beneath it are incremental. This 
    query shows why that asymmetry is correct rather than lazy. 
    
    Record the 2026-02-28 figures after Day 1. Compare them after Day 2.
    
    =========================================================================== 
*/

use role DBT_TRAINING_ANALYST;
use warehouse DBT_TRAINING_BI_WH;


-- ---------------------------------------------------------------------------
-- 1. The aggregate for the two February days.
--
-- RUN AFTER DAY 1 and write the numbers down. Then run again after Day 2:
-- the row for truck 4 on 2026-02-28 has MORE revenue than it did, because
-- the late-arriving order 1099 landed on a day that was already summarised.
-- ---------------------------------------------------------------------------
select 
    business_date 
    , truck_id 
    , truck_name 
    , order_count 
    , units_sold 
    , gross_revenue 
    , gross_margin 
    , gross_margin_pct 
    , avg_order_value
    
from DBT_TRAINING_DB.DEV_MARTS.AGG_DAILY_TRUCK_PERFORMANCE
where business_date in ('2026-02-27', '2026-02-28')
order by 
    business_date
    , truck_id
;

/* 
    The point to make out loud: NOBODY TOLD THE AGGREGATE TO RECALCULATE 
    2026-02-28. It has no watermark, no incremental logic, no knowledge that 
    anything changed. It simply rebuilds from whatever the facts currently say, 
    every single run, and is therefore correct by construction. 
    
    Had it been incremental — "only compute days since the last run" — it would 
    never have revisited 2026-02-28 and would now disagree with fct_orders. The 
    disagreement would be small, permanent, and extremely tedious to find. 
*/

-- ---------------------------------------------------------------------------
-- 2. Does the aggregate agree with the fact it was built from?
--
-- In production, run this on a schedule. An aggregate silently drifting
-- from its base fact is one of the most common warehouse defects, and one
-- of the least often monitored.
-- ---------------------------------------------------------------------------
with from_aggregate as ( 
    select 
        business_date
        , sum(gross_revenue) as revenue 
        
    from DBT_TRAINING_DB.DEV_MARTS.AGG_DAILY_TRUCK_PERFORMANCE 
    group by 1
),

from_fact as ( 
    select 
        order_date as business_date
        , sum(line_gross_revenue) as revenue 
        
    from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDER_LINES 
    group by 1
)

select 
    coalesce(a.business_date, f.business_date) as business_date 
    , a.revenue as aggregate_revenue 
    , f.revenue as fact_revenue
    
    , round(
        coalesce(a.revenue,0) - coalesce(f.revenue,0)
        , 2
    ) as difference 
    
    , case 
        when round(coalesce(a.revenue,0) - coalesce(f.revenue,0), 2) = 0 
            then 'OK' 
        else '*** DRIFT ***' 
    end as status
    
from from_aggregate a
full outer join from_fact f 
    on a.business_date = f.business_date
order by 1
;

/* 
    Every row should read OK. 
*/


-- ---------------------------------------------------------------------------
-- 3. Truck 4 goes off the road — visible in the aggregate after Day 3.
--
-- It went into MAINTENANCE on 2026-03-02 and took no orders that day. Note
-- that it does NOT vanish from dim_truck; it simply stops appearing in the
-- daily performance rows, which is the correct behaviour. A truck with no
-- trading is absent from a sales aggregate, not a zero.
--
-- (If the business wants explicit zero rows for non-trading trucks, that
-- is a deliberate choice: cross join dim_truck to dim_date and left join
-- the facts. Worth mentioning as an exercise — it is the classic
-- "dense vs sparse fact" decision, and it belongs to the modeller, not to
-- the tool.)
-- ---------------------------------------------------------------------------
select 
    business_date 
    , truck_id 
    , truck_name 
    , truck_status 
    , order_count 
    , gross_revenue
    
from DBT_TRAINING_DB.DEV_MARTS.AGG_DAILY_TRUCK_PERFORMANCE
where truck_id in (4, 5)
order by 
    truck_id
    , business_date
;

/* 
    Truck 4: rows up to 2026-03-01, then nothing. 
    Truck 5: nothing until 2026-03-02, then rows — it entered service. 
    
    Both changes flowed through from a source UPDATE and a source INSERT, with 
    no change whatsoever to the dbt project. 
*/

-- ---------------------------------------------------------------------------
-- 4. The trading summary the business would actually look at.
-- Worth ending the session on something that looks like a real report.
-- ---------------------------------------------------------------------------
select 
    truck_name 
    , franchisee_name 
    , count(distinct business_date) as trading_days 
    , sum(order_count) as orders 
    , sum(units_sold) as units 
    , sum(gross_revenue) as revenue 
    , sum(gross_margin) as margin 
    , round(sum(gross_margin) / nullif(sum(gross_revenue), 0), 4) as margin_pct 
    , round(avg(avg_order_value), 2) as avg_order_value
    
from DBT_TRAINING_DB.DEV_MARTS.AGG_DAILY_TRUCK_PERFORMANCE
group by 
    truck_name
    , franchisee_name
order by revenue desc
;

