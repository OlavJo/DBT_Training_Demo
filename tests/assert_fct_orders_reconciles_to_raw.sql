/* 
    assert_fct_orders_reconciles_to_raw 
    --------------------------------------------------------------------------- 
    SINGULAR TEST. Fails if the number of completed orders in the mart does 
    not equal the number of completed orders in the source. 
    
    A singular test is simply a .sql file in tests/ that returns failing rows. 
    No {% test %} block, no arguments, no reusability — it tests one specific 
    thing about this specific project. Use them when the assertion is not 
    general enough to be worth parameterising. 
    
    --------------------------------------------------------------------------- 
    WHY THIS IS THE MOST VALUABLE TEST IN THE PROJECT 
    --------------------------------------------------------------------------- 
    Every other test checks the mart against ITSELF — keys are unique, values 
    are not negative, references resolve. All of those can pass beautifully 
    while the mart is quietly missing a fortnight of orders. 
    
    This test is the only one that checks the mart against REALITY. 
    
    It is precisely the test that catches the Day 2 failure. Watermark on 
    order_ts instead of _loaded_at, and the late-arriving order 1099 never 
    reaches the fact table. Nothing else in the suite notices — the fact table 
    is internally perfect, every key unique, every relationship intact. It is 
    just short one real order and $46 of real revenue. 
    
    Run this test with the wrong watermark in fct_orders and it fails with a 
    one-row difference. That is the moment the abstract argument about 
    ingestion time versus business time becomes a red line in the terminal. 
    
    Reconciliation tests against source are unglamorous, mildly annoying to 
    maintain, and the first thing to catch a genuine data loss. Write them.
*/

with mart_count as ( 
    select count(*) as order_count 
    from {{ ref('fct_orders') }}
),

source_count as ( 
    select count(*) as order_count 
    from {{ source('tasty_bytes_raw', 'order_header') }} 
    where upper(trim(order_status)) = 'COMPLETED'
),

comparison as ( 
    select 
        mart_count.order_count as mart_orders 
        , source_count.order_count as source_orders
        , mart_count.order_count - source_count.order_count as difference 
        
    from mart_count 
    cross join source_count
)
-- Returns a row only when the two disagree.
select * 
from comparison
where difference <> 0
