/* 
    dim_menu_item 
    --------------------------------------------------------------------------- 
    One row per menu item, at its CURRENT price. Type 1.
    
    Menu item 7 rises from $9.00 to $10.50 on Day 2 and this dimension simply 
    shows the new price. 
    
    That is safe ONLY because the fact tables never look their prices up from 
    here — every order line carries the price it was actually sold at. Change 
    that one design decision and this Type 1 dimension would silently reprice 
    the entire sales history every time somebody adjusted a menu. 
    
    Worth stating plainly during the session: the reason a Type 1 dimension is 
    acceptable here is a property of the FACT table, not of the dimension. The 
    two decisions are made together, and reviewing one without the other is 
    how warehouses end up with restating history nobody ordered. 
    
    The price on this dimension remains genuinely useful for a different 
    question — comparing what an item sells for today against what it sold 
    for on a given line reveals which sales happened at prices no longer 
    offered. int_order_lines_enriched keeps both columns for exactly that.
*/

with menu_items as (
    select * from {{ ref('stg_menu_items') }}
),

final as ( 
    select 
            {{ generate_surrogate_key(['menu_item_id']) }} as menu_item_key 
        , menu_item_id 
        , menu_type_id 
        , item_name 
        , item_category 
        , is_healthy 
        
        -- CURRENT values. Facts carry their own historical price. 
        , current_sale_price_usd 
        , current_cost_of_goods_usd 
        , round(current_sale_price_usd - current_cost_of_goods_usd, 2) 
            as current_unit_margin_usd 
        , round( 
            (current_sale_price_usd - current_cost_of_goods_usd) 
                / nullif(current_sale_price_usd, 0), 4 
        ) as current_margin_pct 
        
    from menu_items
)

select * from final
