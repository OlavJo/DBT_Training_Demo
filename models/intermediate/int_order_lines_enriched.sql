/* 
    int_order_lines_enriched 
    --------------------------------------------------------------------------- 
    Order lines with menu attributes and the line-level economics attached. 
    
    WHY THIS MODEL EXISTS 
    --------------------------------------------------------------------------- 
    It joins, and staging may not. That is the short version. 
    The longer version is about which price to use, and it is the kind of 
    detail that quietly ruins a revenue report: 
    
        REVENUE uses unit_price_usd from the ORDER LINE — the price the customer 
        actually paid, captured by the till at the moment of sale. 
        
        COST uses current_cost_of_goods_usd from the MENU ITEM — because the 
        source gives us no historical cost, only today's. 
        
    Those two are not symmetrical, and pretending otherwise would be worse 
    than admitting it. Restating margin for past periods every time a supplier 
    price changes is a real limitation of this model, and it is documented in 
    the yml rather than left for someone to discover. The proper fix is for 
    the source to record cost on the transaction, or for a cost snapshot to 
    exist — either way it is a source problem, not a modelling one. 
    
    Menu item 7 rises from $9.00 to $10.50 on Day 2. Watch what happens: lines 
    sold before the change keep $9.00 in line_gross_revenue, while the 
    dimension shows $10.50. Both correct, and the reason revenue is computed 
    from the transaction price rather than looked up.
*/

with order_lines as ( 
    select * from {{ ref('stg_order_lines') }}
),

menu_items as ( 
    select * from {{ ref('stg_menu_items') }}
),

enriched as ( 
    select 
        -- ids 
        order_lines.order_line_id 
        , order_lines.order_id 
        , order_lines.menu_item_id 
        , order_lines.line_number 
        
        -- menu attributes at their CURRENT values 
        , menu_items.item_name 
        , menu_items.item_category 
        , menu_items.menu_type_id 
        , menu_items.is_healthy
        
        -- --------------------------------------------------------------- 
        -- Line economics. 
        -- 
        -- revenue -> transaction price (historically accurate) 
        -- cost -> current standard cost (the best the source offers) 
        -- --------------------------------------------------------------- 
        , order_lines.quantity 
        , order_lines.unit_price_usd 
        , order_lines.line_gross_revenue 
        , round(order_lines.quantity 
                * coalesce(menu_items.current_cost_of_goods_usd, 0), 2)
                as line_cogs 
        , round(order_lines.line_gross_revenue 
                - (order_lines.quantity * coalesce(menu_items.current_cost_of_goods_usd, 0)), 2) 
                as line_gross_margin 
                
        -- current menu price, kept alongside for price-change analysis. 
        -- Comparing this with unit_price_usd shows which lines were sold at 
        -- a price that is no longer offered. 
        , menu_items.current_sale_price_usd 
        
        -- ingestion time. Bumped on restatement — see day 3. 
        , order_lines.loaded_at 
        
    from order_lines 
    left join menu_items 
        on order_lines.menu_item_id = menu_items.menu_item_id
)

select * from enriched
