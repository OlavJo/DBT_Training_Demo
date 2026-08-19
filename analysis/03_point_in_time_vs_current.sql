/* 
    =========================================================================== 
    EVIDENCE 03 — POINT-IN-TIME vs CURRENT-STATE ATTRIBUTION 
    =========================================================================== 
    RUN AS: DBT_TRAINING_ANALYST 
    WHEN: After Day 2. Re-run after Day 3. 
    
    --------------------------------------------------------------------------- 
    THIS IS THE ONE. If only one query from this project goes on a slide, this 
    is it. 
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
        
    The second question is the one you cannot answer without a snapshot, and 
    it is the one finance will ask. It is also the only version that reproduces 
    the report you published in March — with current-state attribution, last 
    quarter's numbers change every time somebody moves house. 
    =========================================================================== 
*/

use role DBT_TRAINING_ANALYST;
use warehouse DBT_TRAINING_BI_WH;


-- ---------------------------------------------------------------------------
-- THE COMPARISON. Two columns, side by side, from one fact table.
-- Note that both joins are FROM THE SAME ROWS — only the key differs.
-- ---------------------------------------------------------------------------
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


/* 
    AFTER DAY 2, expect a row where the two cities disagree: 
    
        city_today      city_at_sale        flag            revenue 
        Denver          Denver                              ... 
        Denver          Seattle             <-- DISAGREES   107.00 
        Seattle         Seattle                             ... 
        
    That middle row is ALL of customer 3's trading up to and including 
    2026-03-01 — orders 1003, 1009, 1012, 1022 and 1030 — every one of them 
    placed while she still lived in Seattle. 
    
    AFTER DAY 3 a second row appears for her, Denver/Denver, worth 35.50: 
    orders 1040 and 1046, placed after the move. The same customer now 
    contributes to two cities, correctly, in the same query. 
    
    A hundred and seven dollars, in a toy data set. Scale it to a real 
    customer base with normal churn and relocation rates, and it is the 
    difference between a reconciled quarter and an awkward meeting. 
*/


/*  --------------------------------------------------------------------------- 
    THE TOTALS. The same revenue, split two ways. The grand total is identical 
    — no money has appeared or vanished — but the CITY BREAKDOWN differs, which 
    is exactly the kind of discrepancy that is invisible until someone compares 
    two reports built by two people on two different days. 
    --------------------------------------------------------------------------- 
*/
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


/*  --------------------------------------------------------------------------- 
    WHICH SALES ARE AFFECTED? The fact table flags them directly, so you never 
    have to go looking. Any row where customer_has_changed_since is true is a 
    row where the two methods will disagree. 
    
    Useful in production as a monitoring query: if this count starts climbing, 
    your current-state reports are drifting further from history every month. 
    --------------------------------------------------------------------------- 
*/
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

/*  --------------------------------------------------------------------------- 
    AFTER DAY 3, run this too. 
    
    Customer 1 was upgraded BRONZE -> GOLD. Ask "how much revenue comes from 
    GOLD members?" and the two answers diverge again — but this time the 
    business consequence is sharper than geography. 
    
    Attribute by CURRENT tier and every sale customer 1 ever made retroactively 
    becomes GOLD revenue. The loyalty programme then appears to have been 
    generating GOLD revenue months before anyone was upgraded, and any analysis 
    of "what does upgrading a customer actually earn us?" is circular. 
    
    Point-in-time attribution is the only way to measure the effect of a change
    on the thing that changed. 
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
