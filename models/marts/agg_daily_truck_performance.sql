/* 
    agg_daily_truck_performance 
    --------------------------------------------------------------------------- 
    Revenue, margin and volume per truck per day. Grain: date x truck. 
    
    MATERIALISED AS A TABLE, REBUILT IN FULL ON EVERY RUN — and the contrast 
    with the incremental facts beside it is the lesson. 
    
    Why not make this incremental too? Because it would be wrong. 
    
    On Day 2, the late-arriving order 1099 lands with a business date of 
    2026-02-28 — a day this aggregate already summarised on Day 1. An 
    incremental build keyed on "new days since last run" would never revisit 
    2026-02-28, and the total for that day would stay stale forever, quietly 
    disagreeing with fct_orders. 
    
    Rebuilding from scratch makes the aggregate correct by construction. It 
    always reflects whatever the fact tables currently say, whenever they 
    said it and however far back the correction reached. 
    
    THE GENERAL RULE 
    --------------------------------------------------------------------------- 
    Incremental materialisation is an optimisation, and like all optimisations 
    it trades correctness guarantees for speed. It is worth it at the base 
    fact grain, where the tables are large and rows are naturally append-mostly. 
    It is rarely worth it for an aggregate, which is small, cheap to rebuild, 
    and — critically — can be invalidated by a change to ANY row beneath it, 
    including rows for periods you thought were closed. 
    
    Evidence query 07 shows this working: the row for 2026-02-28 has a 
    different revenue figure after Day 2 than it had after Day 1, without 
    anyone rerunning history or issuing a backfill.
*/

{{ 
    config(materialized = 'table') 
}}

with orders as ( 
    select * from {{ ref('fct_orders') }}
),

order_lines as ( 
    select * from {{ ref('fct_order_lines') }}
),

trucks as ( 
    select * from {{ ref('dim_truck') }}
),

dates as (
    select * from {{ ref('dim_date') }}
),

-- Aggregate the two facts separately at their own grain, then join. Joining
-- them first would fan the order-level measures out across their lines.
order_metrics as ( 
    select 
        date_key 
        , truck_key 
        , count(*) as order_count 
        , sum(discount_amount) as total_discount 
        , sum(net_revenue) as net_revenue 
        
    from orders 
    group by 1, 2
),

line_metrics as ( 
    select 
        date_key 
        , truck_key 
        , count(*) as line_count 
        , sum(quantity) as units_sold 
        , sum(line_gross_revenue) as gross_revenue 
        , sum(line_cogs) as cogs 
        , sum(line_gross_margin) as gross_margin 
        , count(distinct customer_id) as distinct_customers 
        
    from order_lines 
    group by 1, 2
),

combined as ( 
    select 
        -- keys 
        order_metrics.date_key 
        , order_metrics.truck_key 
        
        -- descriptive attributes, denormalised so the aggregate is usable 
        -- on its own without joining anything 
        , dates.date_day as business_date 
        , dates.year_month 
        , dates.day_of_week_name 
        , dates.is_weekend 
        , trucks.truck_id 
        , trucks.truck_name 
        , trucks.franchisee_name 
        , trucks.truck_status 
        , trucks.primary_location_city 
        
        -- volume 
        , order_metrics.order_count 
        , line_metrics.line_count 
        , line_metrics.units_sold 
        , line_metrics.distinct_customers 
        
        -- money 
        , line_metrics.gross_revenue 
        , order_metrics.total_discount 
        , order_metrics.net_revenue 
        , line_metrics.cogs 
        , line_metrics.gross_margin 
        , round(
            line_metrics.gross_margin 
                / nullif(line_metrics.gross_revenue , 0)
            , 4
        ) as gross_margin_pct 
        
        -- derived 
        , round(
            line_metrics.gross_revenue 
                / nullif(order_metrics.order_count, 0)
                , 2
            ) as avg_order_value 
        , round(
            line_metrics.units_sold 
                / nullif(order_metrics.order_count, 0)
            , 2
        ) as avg_units_per_order 
        
    from order_metrics 
    inner join line_metrics 
        on order_metrics.date_key = line_metrics.date_key 
            and order_metrics.truck_key = line_metrics.truck_key
    left join trucks 
        on order_metrics.truck_key = trucks.truck_key 
    left join dates 
        on order_metrics.date_key = dates.date_key
)

select * from combined
