/* 
    stg_menu_items 
    --------------------------------------------------------------------------- 
    One row per menu item, at its CURRENT price. 
    
    `sale_price_usd` here is today's price. It is renamed to 
    `current_sale_price_usd` to make that unmistakable, because the trap is 
    real: joining a fact table to this column to compute historical revenue 
    would silently reprice every past sale at today's rate. 
    
    Menu item 7 rises from $9.00 to $10.50 on Day 2. After that change: 
      * this model shows $10.50 for every row, 
      * order lines sold before the change still carry $9.00, 
      * and both are correct. 
      
    The fact table stores the transaction price because that is what actually 
    changed hands. A familiar rule for anyone who has built a sales fact —
    and worth stating explicitly, because dbt does not change it.
*/

with source as ( 
    select * from {{ source('tasty_bytes_raw', 'menu_item') }}
),

renamed as ( 

    select 
        -- ids menu_item_id 
        , menu_type_id 
        
        -- attributes 
        , trim(item_name) as item_name 
        , trim(item_category) as item_category 
        , is_healthy_flag as is_healthy 
        
        -- money. CURRENT values — see the note above.
        , cost_of_goods_usd as current_cost_of_goods_usd 
        , sale_price_usd as current_sale_price_usd 
        
        -- audit 
        , _loaded_at as loaded_at 
        
    from source
)

select * from renamed
