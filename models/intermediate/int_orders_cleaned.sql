/* 
    int_orders_cleaned 
    --------------------------------------------------------------------------- 
    Orders, decoded and filtered to the set the business considers real. 
    
    WHY THIS MODEL EXISTS — three jobs staging was not allowed to do 
    --------------------------------------------------------------------------- 
    
        1. JOINS TO SEEDS. 'WLKUP' becomes 'Walk-up'; 'US' becomes 'North 
            America' and 'USD'. Staging mirrors the source and does not join. 
        2. APPLIES A BUSINESS RULE. Cancelled orders are excluded here, in ONE 
            place. Every downstream model and every dashboard inherits that
            definition automatically. 
            
            This is the argument for the intermediate layer in a single line. 
            Without it, `where order_status != 'CANCELLED'` gets copied into 
            four models and eleven dashboards, and eighteen months later two of
            them say 'CANCELED' and nobody can explain the variance. Here, the 
            rule has one home, one definition, and one place to change. 
            
        3. NAMES THE RULE. `is_cancelled` is retained as a column rather than
            being silently dropped, so anyone auditing the model can see what 
            was excluded and count it. 
            
    Note that we keep cancelled orders in the OUTPUT but flag them, and let 
    the fact tables filter. A cancellation is a real business event — you 
    want to be able to count them and analyse the rate. 
    
    Discarding rows early is irreversible; flagging them is not.
*/

with orders as ( 
    select * from {{ ref('stg_order_headers') }}
),

channels as ( 
    select * from {{ ref('order_channel_map') }}
),

countries as ( 
    select * from {{ ref('country_region') }}
),

locations as ( 
    select * from {{ ref('stg_locations') }}
),

joined as ( 
    select 
        -- ids 
        orders.order_id 
        , orders.truck_id 
        , orders.customer_id 
        , orders.location_id 
        
        -- business time 
        , orders.order_ts 
        , orders.order_date 
        
        -- --------------------------------------------------------------- 
        -- Decoded channel. The seed turns POS shorthand into language a 
        -- business user recognises — and, just as usefully, means the 
        -- mapping is reviewable in a pull request rather than buried in a 
        -- CASE statement halfway down a model. 
        -- --------------------------------------------------------------- 
        , orders.order_channel_code 
        , channels.channel_name as order_channel_name 
        , channels.is_digital as is_digital_channel 
        , channels.channel_group as order_channel_group 
        
        -- geography, resolved through the location and the country seed 
        , locations.city as location_city 
        , locations.region as location_region 
        , locations.country as location_country 
        , countries.region as reporting_region 
        , countries.currency_code as reporting_currency 
        
        -- status, with the business rule made explicit 
        , orders.order_status 
        , orders.order_status = 'CANCELLED' as is_cancelled 
        
        -- money 
        , orders.order_currency 
        , orders.discount_amount
        
        -- ingestion time, carried through for the incremental watermark 
        , orders.loaded_at 
        
    from orders 
    left join channels 
        on orders.order_channel_code = channels.channel_code 
    left join locations 
        on orders.location_id = locations.location_id 
    left join countries 
        on locations.country = countries.country
        
)

select * from joined
