/* 
    assert_no_orphan_order_lines 
    --------------------------------------------------------------------------- 
    SINGULAR TEST. Fails if any order line in the source has no matching order 
    header, or if any completed order has no lines at all. 
    
    TWO ASSERTIONS IN ONE FILE, which is normally poor practice — a failing 
    test should point at one thing. They are together here because they are 
    two halves of a single claim: the parent/child relationship between orders 
    and their lines is intact in both directions. 
    
    --------------------------------------------------------------------------- 
    WHY BOTH DIRECTIONS MATTER 
    --------------------------------------------------------------------------- 
    A LINE WITHOUT A HEADER is the obvious case, and the `relationships` test 
    in _staging__sources.yml already covers it. It is repeated here against 
    RAW rather than staging because this test runs against the SOURCE, and the 
    point is to catch the problem before it has been through any modelling. 
    
    AN ORDER WITHOUT LINES is the case people forget, and it is the more 
    interesting one. It does not violate any foreign key. Nothing is null. 
    `relationships` will never fire, because that test only looks for children 
    pointing at missing parents, not for parents with no children. 
    
    What it produces is an order in fct_orders with a gross_revenue of zero — 
    because the LEFT JOIN to int_orders_with_lines found nothing and the 
    coalesce did its job. The order count is right. The revenue is quietly 
    short. Average order value drifts downward by an amount nobody can 
    explain, and the discrepancy scales with however many orders are affected. 
    
    In practice this happens when the header and line feeds are loaded 
    separately and one of them is late or partial — which is exactly what 
    the two-table ingestion in this project simulates. 
    It is a very common real defect and often never tested for. 
    
    --------------------------------------------------------------------------- 
    Note this test runs against RAW, not against the marts. That is 
    deliberate: it is a statement about whether the SOURCE DATA is coherent, 
    not about whether the modelling is correct. Keeping those two kinds of 
    assertion separate makes a failure much faster to diagnose — you 
    immediately know whether to talk to the upstream team or read your own 
    SQL.
*/

with orphan_lines as ( 
    select 
        'order line with no header' as failure_type 
        , order_line.order_line_id as failing_id 
        , order_line.order_id as related_order_id 
    from {{ source('tasty_bytes_raw', 'order_line') }} as order_line 
    left join {{ source('tasty_bytes_raw', 'order_header') }} as order_header 
        on order_line.order_id = order_header.order_id 
    where order_header.order_id is null
    
),

childless_orders as ( 
    select 
        'completed order with no lines' as failure_type 
        , order_header.order_id as failing_id 
        , order_header.order_id as related_order_id 
    from {{ source('tasty_bytes_raw', 'order_header') }} as order_header
    left join {{ source('tasty_bytes_raw', 'order_line') }} as order_line 
        on order_header.order_id = order_line.order_id 
    where order_line.order_id is null 
        and upper(trim(order_header.order_status)) = 'COMPLETED'
        
)

select * from orphan_lines
union all
select * from childless_orders
