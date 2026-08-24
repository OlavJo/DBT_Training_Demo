{{ config(materialized = 'ephemeral') }}

/* 
    int_orders_with_lines 
    --------------------------------------------------------------------------- 
    Order lines rolled up to ORDER grain, ready to join to the order header. 
    
    MATERIALISED AS EPHEMERAL — the one worked example in this project. 
    --------------------------------------------------------------------------- 
    Nothing is created in the database. dbt inlines this as a CTE inside 
    fct_orders, its only consumer. Sensible here because it is a single-use 
    stepping stone, and creating a view for it would add an object to the 
    schema that no human will ever query. 
    
    The cost: you cannot SELECT * from it to debug, it does not appear in 
    Snowsight's object browser, and it makes the compiled SQL of fct_orders 
    deeper. That is why every OTHER intermediate model in this project is a 
    view. 
    
    Ephemeral is right for a private helper with exactly one consumer; 
    it is a poor default. 
    
    WHY THIS MODEL EXISTS — fan-out control 
    --------------------------------------------------------------------------- 
    An order has many lines. Join the header straight to the lines and you get 
    one row per LINE, not per ORDER. Any sum over a header column — the 
    discount, say — is then multiplied by the line count. 
    
    That class of bug is quiet. Nothing errors; the totals are simply too big, 
    by an amount that varies with basket size. Aggregating to the target grain 
    BEFORE joining makes it structurally impossible. 
    
    A familiar discipline for anyone who has built a fact table: dbt does not 
    protect you from grain errors. It gives you somewhere to put the guard, 
    and a test (see fct_orders) that proves the guard is working. 
    
    THE WATERMARK PROBLEM — read this before touching fct_orders 
    --------------------------------------------------------------------------- 
    On Day 3, order line 10281 is restated. Its loaded_at moves to 
    2026-03-03. The HEADER of order 1028 does not change at all — its
    loaded_at stays at 2026-03-02. 
    
    So an incremental fact filtering on the header's loaded_at alone would 
    never revisit order 1028, and its total would remain wrong forever. 
    
    The fix is `order_effective_loaded_at` below: the latest ingestion time 
    across the order AND all of its lines. That is the column fct_orders 
    watermarks on. 
    
    The general rule, which applies to any parent/child fact: THE WATERMARK 
    MUST REFLECT EVERY TABLE THAT CAN CHANGE THE ROW. Watermark on the parent 
    alone and child-only corrections are lost silently.
*/

with order_lines as ( 
    select * from {{ ref('int_order_lines_enriched') }}
),

aggregated as ( 
    select 
        order_id 
        
        -- line counts 
        , count(*) as line_count 
        , sum(quantity) as total_units 
        
        -- money, summed at the correct grain 
        , round(sum(line_gross_revenue), 2) as order_gross_revenue 
        , round(sum(line_cogs), 2) as order_cogs 
        , round(sum(line_gross_margin), 2) as order_gross_margin 
        
        -- ----------------------------------------------------------------- 
        -- The latest moment any LINE of this order arrived or was corrected. 
        -- Combined with the header's own loaded_at in fct_orders to form the 
        -- effective watermark. See the note above — this single column is 
        -- what makes restatements land. 
        -- ----------------------------------------------------------------- 
        , max(loaded_at) as lines_last_loaded_at 
        
    from order_lines 
    group by order_id
)

select * from aggregated
