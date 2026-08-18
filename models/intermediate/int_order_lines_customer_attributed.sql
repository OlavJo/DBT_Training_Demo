/* 
    int_order_lines_customer_attributed 
    =========================================================================== 
    THE POINT-IN-TIME JOIN. This is the model the snapshots exist for. 
    =========================================================================== 
    
    Every order line is resolved to the version of the customer that was in force 
    AT THE MOMENT OF THE SALE — not the version that happens to be current today. 
    
    WHY THIS MATTERS 
    --------------------------------------------------------------------------- 
    Customer 3, Chloe Nguyen, lived in Seattle and bought from Seattle trucks 
    on 27 and 28 February. On 2 March she moved to Denver. 
    
    Ask "how much revenue came from Seattle customers in February?" and there 
    are two defensible answers: 
    
    CURRENT-STATE ATTRIBUTION 
        Join the fact to today's customer record. Chloe is in Denver, so her 
        February spend counts as Denver. Correct if the question is really 
        "what is my Denver customer base worth?" — you are segmenting today's 
        customers and looking at their history. 
        
    POINT-IN-TIME ATTRIBUTION 
        Join the fact to the customer as they were that day. Chloe was in 
        Seattle, so her February spend counts as Seattle. Correct if the 
        question is "what did February actually look like?" — and it is the 
        only answer that reproduces the report you published in March.
        
    Both are right. They answer different questions. What is NOT acceptable is 
    being unable to produce the second one — and without a snapshot you cannot, 
    because the source overwrote Seattle the moment she moved. 
    
    The failure mode is worse than a wrong number: it is a February report 
    that changes every time you rerun it, with no audit trail explaining why. 
    Anyone who has had to explain to a finance director why last quarter's 
    figures moved will recognise the problem immediately. 
    
    HOW THE JOIN WORKS 
    --------------------------------------------------------------------------- 
        order_ts >= effective_valid_from AND order_ts < valid_to 
        
    A BETWEEN across the version's validity window. Because snap_customer sets 
    dbt_valid_to_current, the open-ended current version carries 9999-12-31 
    rather than NULL, so this is a plain comparison with no null handling. 
    
    effective_valid_from rather than valid_from — see int_customer_scd. The 
    first version is backdated so that orders predating the first snapshot run 
    still resolve. 
    
    Two invariants make this join safe, and both are enforced by tests in 
    _marts__models.yml rather than assumed: 
    
      * no customer has two versions valid at the same instant (no fan-out) 
      * every customer has exactly one current version (no gaps) 
      
    A point-in-time join against a broken SCD2 table silently duplicates 
    revenue. Test the dimension, not just the fact.
*/

with order_lines as ( 
    select * from {{ ref('int_order_lines_enriched') }}
),

orders as ( 
    select * from {{ ref('int_orders_cleaned') }}
),

customer_history as ( 
    select * from {{ ref('int_customer_scd') }}
),

-- Bring the order's context down to line grain. The header is joined 1:many
-- onto its lines, which is correct here — the OUTPUT grain is the line.
lines_with_order_context as ( 
    select 
        order_lines.order_line_id 
        , order_lines.order_id 
        , order_lines.menu_item_id 
        , order_lines.line_number 
        , order_lines.item_name 
        , order_lines.item_category 
        , order_lines.is_healthy 
        , order_lines.quantity 
        , order_lines.unit_price_usd 
        , order_lines.line_gross_revenue 
        , order_lines.line_cogs 
        , order_lines.line_gross_margin 
        , order_lines.loaded_at as line_loaded_at 
        , orders.customer_id 
        , orders.truck_id 
        , orders.location_id 
        , orders.order_ts 
        , orders.order_date 
        , orders.order_channel_code 
        , orders.order_channel_name 
        , orders.is_digital_channel 
        , orders.order_channel_group 
        , orders.location_city 
        , orders.reporting_region 
        , orders.order_status 
        , orders.is_cancelled
        , orders.discount_amount as order_discount_amount 
        , orders.loaded_at as order_loaded_at 
    from order_lines 
    inner join orders 
        on order_lines.order_id = orders.order_id
        
),

attributed as (
    select 
        lines_with_order_context.* 
        
        -- --------------------------------------------------------------- 
        -- The customer AS THEY WERE at the moment of sale. 
        -- --------------------------------------------------------------- 
        , customer_history.customer_version_id as customer_version_id_at_order 
        
        -- The raw validity start of the matched version. fct_order_lines 
        -- hashes (customer_id, this) to build customer_history_key, which 
        -- MUST match dim_customer_history.customer_history_key exactly — 
        -- the same two columns, hashed by the same macro, in the same order. 
        -- Get this wrong and the point-in-time join returns nothing, quietly. 
        , customer_history.valid_from as customer_valid_from_at_order 
        , customer_history.city as customer_city_at_order 
        , customer_history.postal_code as customer_postal_code_at_order 
        , customer_history.loyalty_tier as customer_tier_at_order 
        , customer_history.country as customer_country_at_order 
        , customer_history.version_number as customer_version_at_order 
        
        -- Did this sale happen under a customer record that has since 
        -- changed? A useful diagnostic: rows where this is true are exactly 
        -- the rows where the two attribution methods disagree. 
        , not customer_history.is_current as customer_has_changed_since 
        
    from lines_with_order_context 
    left join customer_history 
        on lines_with_order_context.customer_id = customer_history.customer_id 
            and lines_with_order_context.order_ts >= customer_history.effective_valid_from 
            and lines_with_order_context.order_ts < customer_history.valid_to
            
),

-- The effective ingestion watermark for this line: the later of when the
-- line arrived and when its order header arrived. See int_orders_with_lines
-- for why a parent/child fact must consider both.
final as ( 
    select 
        attributed.* , 
        greatest(line_loaded_at, order_loaded_at) as effective_loaded_at 
    from attributed
    
)

select * from final
