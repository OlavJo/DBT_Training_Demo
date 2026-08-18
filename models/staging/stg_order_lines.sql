/* 
    stg_order_lines 
    --------------------------------------------------------------------------- 
    One row per item on an order. This is the finest grain in the warehouse. 
    
    `unit_price_usd` is the price at the moment of sale, captured by the till. 
    It is NOT looked up from the menu, and must never be — see stg_menu_items. 
    
    RESTATEMENTS. Rows in this table can change after the fact. On Day 3, 
    order line 10281 has its quantity corrected from 2 to 5 and its loaded_at 
    bumped, with the same order_line_id. That is why: 
    
      * order_line_id remains genuinely unique (the row was updated, not 
        duplicated), and 
      * fct_order_lines must MERGE on that key rather than append, or the 
        correction becomes a duplicate and revenue is overstated. 
        
    Line revenue is computed here because it is arithmetic on two columns of
    the same row, not business logic. Cost, margin and anything requiring the 
    menu item belong in int_order_lines_enriched, where the join lives.
*/

with source as ( 
    select * from {{ source('tasty_bytes_raw', 'order_line') }}
),

renamed as (
    select 
        -- ids 
        order_line_id 
        , order_id 
        , menu_item_id 
        , line_number

        -- measures 
        , quantity 
        , unit_price_usd 
        , round(quantity * unit_price_usd, 2) as line_gross_revenue 
        
        -- ingestion time. Bumped on restatement — this is how a corrected 
        -- line gets picked up by the next incremental run. 
        , _loaded_at as loaded_at 
    from source
    
)

select * from renamed
