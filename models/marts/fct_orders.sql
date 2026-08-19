{{ 
    config( 
        materialized = 'incremental', 
        unique_key = 'order_key', 
        incremental_strategy = 'merge', 
        on_schema_change = 'append_new_columns' 
    )
}}

/* 
    fct_orders 
    =========================================================================== 
    One row per COMPLETED order. Incremental. 
    =========================================================================== 
    
    Cancelled orders are excluded, applying the rule defined once in 
    int_orders_cleaned. That makes this "the completed sales fact", and every 
    reconciliation against source counts completed orders only. The trade-off 
    is that cancellation rate cannot be analysed from this table — it is 
    available from int_orders_cleaned, which flags rather than drops.
    
    --------------------------------------------------------------------------- 
    THE INCREMENTAL CONFIGURATION — three decisions, all of them load-bearing 
    --------------------------------------------------------------------------- 
    
    1. incremental_strategy = 'merge' (not 'append') 
    
        On Day 3, order line 10281 is restated: quantity corrected from 2 to 5. 
        Order 1028 already exists in this table with the wrong total. 
        
        APPEND would insert a SECOND row for the same order. The table would 
        hold both the wrong figure and the right one, the row count would rise, 
        and revenue would be overstated. Nothing would error. No test would 
        fail unless you wrote one. The books would simply be wrong. 
        
        MERGE matches on unique_key and updates the existing row in place. 
        Row count unchanged, revenue corrected. 
        
    2. unique_key = 'order_key' 
    
        Without this, merge has nothing to match on. With the wrong column, it 
        matches the wrong rows and quietly corrupts the table. This is the most 
        consequential single line in the model. 
        
    3. on_schema_change = 'append_new_columns' 
    
        When you add a column to this model, dbt adds it to the existing table 
        rather than failing the run or silently ignoring it. The default is 
        'ignore', which is a surprising thing to discover in production three 
        weeks after your new column stopped appearing. 
        
    --------------------------------------------------------------------------- 
    THE WATERMARK — the single most important filter in this project 
    --------------------------------------------------------------------------- 
    
    The natural instinct is to take everything newer than the newest row you 
    already have, by business date: 
    
        where order_date > (select max(order_date) from {{ this }}) -- WRONG 
        
    Try it. It works perfectly on Day 1 and it is silently, permanently wrong 
    on Day 2. 
    
    Order 1099 was placed at 19:30 on 2026-02-28 but only reached the 
    warehouse at 06:00 on 2026-03-02, because the truck's payment terminal 
    was offline. By the time it arrives, max(order_date) is already 
    2026-03-01. The filter excludes it. A real $46 sale is dropped, revenue 
    for 2026-02-28 is understated forever, and nothing anywhere reports a 
    problem. 
    
    The filter below uses effective_loaded_at — INGESTION time — so "new to 
    us" means what it says, regardless of when the sale happened. The late 
    order is picked up on the next run and filed under the correct business 
    date. 
    
    TWO REFINEMENTS THAT ARE EASY TO MISS 
    
        (a) effective_loaded_at is the LATER of the header's arrival and its 
            lines' arrival. A restatement touches only the line — the header's 
            loaded_at never moves — so watermarking on the header alone would miss 
            every child-only correction. Any parent/child fact needs this. 
        
        (b) The lookback window. Rather than taking strictly newer than the last 
            watermark, the filter reaches back a few days. Ingestion timestamps 
            are not perfectly ordered: a load that is running while the previous 
            one commits can produce rows whose loaded_at is fractionally earlier 
            than a watermark already recorded. Those rows would sit forever in the 
            blind spot between the two runs. 
            
            Re-reading a few days is cheap and, because merge is idempotent, 
            completely safe. Rows already present are simply rewritten with 
            identical values. Set the window wider than your worst expected load 
            delay — it is one of the few places where being generous costs almost 
            nothing and being tight costs you data.
*/

with orders as ( 
    select * from {{ ref('int_orders_cleaned') }}
),

order_lines_rollup as ( 
    select * from {{ ref('int_orders_with_lines') }}
),

joined as ( 
    select 
        -- --------------------------------------------------------------- 
        -- Keys 
        -- --------------------------------------------------------------- 
            {{ generate_surrogate_key(['orders.order_id']) }} as order_key 
        , orders.order_id 
        
        -- foreign keys into the dimensions, hashed the same way 
        , {{ generate_surrogate_key(['orders.customer_id']) }} as customer_key 
        , {{ generate_surrogate_key(['orders.truck_id']) }} as truck_key 
        , {{ generate_surrogate_key(['orders.location_id']) }} as location_key 
        , to_number(to_char(orders.order_date, 'YYYYMMDD')) as date_key 
        
        -- natural keys, retained for reconciliation against source 
        , orders.customer_id 
        , orders.truck_id 
        , orders.location_id 
        
        -- --------------------------------------------------------------- 
        -- Degenerate dimensions — attributes of the order itself, with no 
        -- dimension table of their own. Standard practice, and they live 
        -- on the fact rather than forcing a one-column dimension. 
        -- --------------------------------------------------------------- 
        , orders.order_ts 
        , orders.order_date 
        , orders.order_channel_code 
        , orders.order_channel_name 
        , orders.order_channel_group 
        , orders.is_digital_channel 
        , orders.order_status 
        , orders.order_currency 
        
        -- --------------------------------------------------------------- 
        -- Measures. Additive at this grain. 
        -- --------------------------------------------------------------- 
        , coalesce(order_lines_rollup.line_count, 0) as line_count 
        , coalesce(order_lines_rollup.total_units, 0) as total_units 
        , coalesce(order_lines_rollup.order_gross_revenue, 0) as gross_revenue 
        , coalesce(order_lines_rollup.order_cogs, 0) as cogs 
        , coalesce(order_lines_rollup.order_gross_margin, 0) as gross_margin 
        , orders.discount_amount 
        , round(
            coalesce(order_lines_rollup.order_gross_revenue, 0) 
                - orders.discount_amount
                , 2
            ) as net_revenue 
            
        -- --------------------------------------------------------------- 
        -- Audit columns. effective_loaded_at is the watermark; the others 
        -- make it possible to SEE the late arrival in the data. 
        -- --------------------------------------------------------------- 
        , orders.loaded_at as order_loaded_at 
        , order_lines_rollup.lines_last_loaded_at 
        , greatest( 
            orders.loaded_at, 
            coalesce(order_lines_rollup.lines_last_loaded_at, orders.loaded_at) 
        ) as effective_loaded_at 
        
        -- How many days after the sale did we find out about it? Zero or one 
        -- for everything except order 1099, which shows 2. 
        , datediff(
            'day', 
            orders.order_date, 
            date(orders.loaded_at)
        ) as ingestion_lag_days 
        
    from orders 
    left join order_lines_rollup 
        on orders.order_id = order_lines_rollup.order_id 
        
    -- The business rule, inherited from int_orders_cleaned. 
    where not orders.is_cancelled
)

select * from joined

{% if is_incremental() %} 
    -- ------------------------------------------------------------------ 
    -- Only rows that arrived (or were corrected) since the last run, 
    -- less a lookback window. Read the long note above before changing 
    -- anything on these four lines. 
    -- ------------------------------------------------------------------ 
    where effective_loaded_at > ( 
        select 
            dateadd( 
                'day', 
                -{{ var('incremental_lookback_days') }}, 
                coalesce(
                    max(effective_loaded_at), 
                    to_timestamp_ntz('1900-01-01 00:00:00')
                ) 
            ) 
        from {{ this }} 
    )
{% endif %}
