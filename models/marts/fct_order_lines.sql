{{ 
    config( 
        materialized = 'incremental', 
        unique_key = 'order_line_key', 
        incremental_strategy = 'merge', 
        on_schema_change = 'append_new_columns' 
    )
}}

/* 
    fct_order_lines 
    =========================================================================== 
    One row per item sold. The finest grain in the warehouse, and the table 
    the semantic view is built on. 
    =========================================================================== 
    
    Incremental configuration follows the same reasoning as fct_orders — see 
    that model for the full commentary on merge, unique_key and the lookback 
    window. The watermark here is effective_loaded_at from 
    int_order_lines_customer_attributed. 
    --------------------------------------------------------------------------- 
    THE DUAL CUSTOMER KEY — the reason this project exists 
    --------------------------------------------------------------------------- 
    This fact carries TWO foreign keys to the customer, and shipping both is 
    the whole argument for snapshots made concrete:

        customer_key 
            Points at dim_customer — the customer as they are TODAY. 
            Join here to ask "what is my Denver customer base worth?" 
            
        customer_history_key 
            Points at dim_customer_history — the customer as they were ON THE 
            DAY OF THE SALE. Join here to ask "what did February actually look 
            like?" 
            
    Customer 3 moved from Seattle to Denver on Day 2. Run the same revenue 
    query through each key and the February numbers differ. Both are correct. 
    Only one of them reproduces the report you published in March. 
    
    Most warehouses offer only the first, because the source overwrote the 
    information needed for the second. Evidence query 03 puts the two side by 
    side, and it is the single most persuasive thing in this project. 
    
    The attributes AT TIME OF ORDER are also carried directly on the fact 
    (customer_city_at_order, customer_tier_at_order) so that the common case 
    needs no join at all — a denormalisation that costs a few bytes and saves 
    every analyst the trouble of getting the validity-window join right.
*/

with attributed_lines as ( 
    select * from {{ ref('int_order_lines_customer_attributed') }}
),

final as ( 
    select 
        -- --------------------------------------------------------------- 
        -- Keys 
        -- --------------------------------------------------------------- 
            {{ generate_surrogate_key(['order_line_id']) }} as order_line_key 
        , {{ generate_surrogate_key(['order_id']) }} as order_key 
        , order_line_id 
        , order_id 
        , line_number 
        
        -- dimension foreign keys 
        , {{ generate_surrogate_key(['customer_id']) }} as customer_key 
        , {{ generate_surrogate_key(['truck_id']) }} as truck_key 
        , {{ generate_surrogate_key(['location_id']) }} as location_key 
        , {{ generate_surrogate_key(['menu_item_id']) }} as menu_item_key 
        , to_number(to_char(order_date, 'YYYYMMDD')) as date_key 
        
        -- --------------------------------------------------------------- 
        -- THE POINT-IN-TIME KEY. 
        -- Built from the customer id and the validity start of the version 
        -- in force at order_ts, so it matches dim_customer_history's 
        -- version-grain key exactly. 
        -- --------------------------------------------------------------- 
        , {{ generate_surrogate_key(['customer_id', 'customer_valid_from_at_order']) }} 
            as customer_history_key 
        , customer_version_id_at_order 
        
        -- natural keys for reconciliation 
        , customer_id 
        , truck_id 
        , location_id 
        , menu_item_id 
        
        -- --------------------------------------------------------------- 
        -- Degenerate dimensions 
        -- --------------------------------------------------------------- 
        , order_ts 
        , order_date 
        , order_channel_code 
        , order_channel_name 
        , order_channel_group 
        , is_digital_channel 
        , item_name 
        , item_category 
        , is_healthy 
        
        -- --------------------------------------------------------------- 
        -- Customer attributes AS AT THE SALE. Denormalised onto the fact 
        -- so the common question needs no validity-window join. 
        -- --------------------------------------------------------------- 
        , customer_city_at_order 
        , customer_postal_code_at_order 
        , customer_tier_at_order 
        , customer_country_at_order 
        , customer_version_at_order 
        , customer_has_changed_since 
        
        -- --------------------------------------------------------------- 
        -- Measures. Fully additive at line grain. 
        -- --------------------------------------------------------------- 
        , quantity 
        , unit_price_usd 
        , line_gross_revenue 
        , line_cogs 
        , line_gross_margin 
        
        -- --------------------------------------------------------------- 
        -- Audit 
        -- --------------------------------------------------------------- 
        , line_loaded_at 
        , order_loaded_at 
        , effective_loaded_at 
        
    from attributed_lines 
    -- Same business rule as fct_orders: completed sales only. 
    where not is_cancelled
)

select * from final

{% if is_incremental() %} 

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
