/* 
    assert_order_line_revenue_ties_to_orders 
    --------------------------------------------------------------------------- 
    SINGULAR TEST. Fails if the sum of line revenue in fct_order_lines does 
    not equal the sum of gross revenue in fct_orders. 
    
    A CROSS-MODEL CONSISTENCY CHECK. The two facts are built from the same 
    source through different paths — fct_orders aggregates lines up to order 
    grain via int_orders_with_lines, while fct_order_lines carries them at 
    line grain through the point-in-time attribution. They must agree. 
    
    This catches a whole family of problems that nothing else will: 
      * a fan-out in the point-in-time join duplicating line revenue 
        (which is exactly what a broken SCD2 dimension causes) 
      * the two facts falling out of step because their incremental runs 
        picked up different rows 
      * the cancellation filter being applied in one model and not the other
      * a rounding difference that looks trivial and compounds 
      
    The tolerance below is one cent, to absorb ordinary decimal rounding 
    across two different aggregation paths. Set it to zero and you will get 
    false failures; set it to a dollar and you will miss real ones. A cent is 
    the right answer for money at this scale. 
    
    Note this is where the Day 3 restatement gets verified end to end. When 
    line 10281 is corrected from 2 to 5, BOTH facts have to move by the same 
    $31.50. If merge worked on one and not the other, this test is what tells 
    you — and it tells you on the run that broke it, not next quarter.
*/

with line_total as ( 
    select 
        round(sum(line_gross_revenue), 2) as total_revenue 
    from {{ ref('fct_order_lines') }}
),

order_total as ( 
    select 
        round(sum(gross_revenue), 2) as total_revenue 
    from {{ ref('fct_orders') }}
),

comparison as ( 
    select 
        line_total.total_revenue as order_lines_revenue 
        , order_total.total_revenue as orders_revenue 
        , round(
            abs(line_total.total_revenue - order_total.total_revenue)
            , 2
        ) as absolute_difference 
    from line_total 
    cross join order_total
    
)

select * from comparison
where absolute_difference > 0.01
