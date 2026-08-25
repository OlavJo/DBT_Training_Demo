/* 
    stg_order_headers 
    --------------------------------------------------------------------------- 
    One row per order, exactly as the source holds them right now. 
    
    STAGING RULES — the same six apply to every model in this folder: 
        1. One staging model per source table. No more, no fewer. 
        2. No joins. 
        3. No business logic filtering of rows. 
        4. No business logic aggregation. 
        5. Rename to the business vocabulary, cast types, tidy whitespace. 
        6. Materialised as a view, so it costs nothing to keep current. 
    
    THE TWO TIMESTAMPS. This model is where the project's central distinction 
    first becomes visible in dbt code: 
    
        order_ts        when the sale happened          BUSINESS time 
        loaded_at       when we found out about it      INGESTION time 
        
    Normally they differ by one overnight batch. For the late-arriving order
    on Day 2 they differ by two days, and everything downstream depends on
    keeping them apart. `order_date` is derived from order_ts because that is 
    what a sale belongs to; the incremental filter in fct_orders reads 
    loaded_at because that is what "new to us" means. 
    
    NOTE ALSO WHAT IS NOT HERE. Cancelled orders are not filtered out, and 
    order_channel is not decoded from 'WLKUP' into 'Walk-up'. Both are 
    tempting one-liners and both are business logic, so both live in 
    int_orders_cleaned instead. Staging mirrors the source; it does not have 
    opinions about it.
*/

with source as (
    select * from {{ source('tasty_bytes_raw', 'order_header') }}
),

renamed as ( 
    select 
        -- ids 
        order_id 
        , truck_id 
        , customer_id 
        , location_id 
        
        -- business time 
        , order_ts 
        , date(order_ts) as order_date 
        
        -- attributes. Raw codes, decoded later against the seed. 
        , upper(trim(order_channel)) as order_channel_code 
        , upper(trim(order_status)) as order_status 
        , upper(trim(order_currency)) as order_currency 
        
        -- money 
        , coalesce(discount_amount, 0) as discount_amount 
        
        -- ingestion time. The incremental watermark for every fact model. 
        , _loaded_at as loaded_at
        
    from source
)

select * from renamed
