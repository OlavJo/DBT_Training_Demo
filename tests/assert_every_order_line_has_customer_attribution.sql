{{ 
    config(store_failures = true) 
}}

/* 
    assert_every_order_line_has_customer_attribution 
    --------------------------------------------------------------------------- 
    SINGULAR TEST. Fails if any order line could not be resolved to a 
    customer version valid at the moment of sale. 
    
    Guards the point-in-time join in int_order_lines_customer_attributed. A 
    gap in the SCD2 validity windows produces NULL attributes rather than an 
    error, and those rows then aggregate into an "unknown city" bucket that 
    everybody ignores. 
    
    The most likely cause is the one described in int_customer_scd: an order 
    predating the first `dbt snapshot` run, where version 1's valid_from 
    starts after the sale. If this test fires on a real project, check whether 
    effective_valid_from is being used rather than valid_from. 
    
    --------------------------------------------------------------------------- 
    store_failures = true — WORTH DEMONSTRATING 
    --------------------------------------------------------------------------- 
    This config tells dbt to write the failing rows to a real table rather 
    than discarding them after printing a count. Look for it in: 
    
        DEV_MARTS_dbt_test__audit.assert_every_order_line_has_customer_attribution 
        
    Why that matters: the default behaviour tells you 47 rows failed. It does 
    not tell you WHICH. So the first thing anyone does after a failed test is 
    reconstruct the query by hand to find out — and on a complicated test they 
    usually reconstruct it slightly wrong. 
    
    With store_failures, the evidence is already sitting in a table. You can 
    query it, join it back to the source, share it with whoever owns the 
    upstream system, and watch the row count fall as they fix things. 
    
    It is not the right default — you would be creating audit tables for every 
    trivial not_null check — but for tests where the failing rows are the 
    thing you actually need, turn it on.
*/

select 
    order_line_key 
    , order_line_id 
    , order_id 
    , customer_id 
    , order_ts 
    , order_date 
    , line_gross_revenue
    
from {{ ref('fct_order_lines') }}
where customer_history_key is null 
    or customer_city_at_order is null
    
