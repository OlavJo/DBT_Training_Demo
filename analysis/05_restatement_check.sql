/* 
    =========================================================================== 
    EVIDENCE 05 — The restatement: merge vs append 
    --------------------------------------------------------------------------- 
    RUN AS: DBT_TRAINING_ANALYST 
    WHEN: BEFORE and AFTER the Day 3 build. The comparison is the point. 
    --------------------------------------------------------------------------- 
    On Day 3, order line 10281 is corrected: quantity 2 -> 5, at $10.50. 
    
    The proof that `merge` worked is TWO facts held together: 
    
        row count       UNCHANGED 
        revenue         UP by exactly $31.50 
        
    Either one alone proves nothing. Revenue rising is what you would expect 
    from a duplicate too. It is the row count staying flat WHILE revenue moves 
    that shows the row was updated in place rather than added again. 
    
    RUN THIS BEFORE THE DAY 3 BUILD and note the numbers. Then run the build 
    and run it again. 
    =========================================================================== 
*/

use role DBT_TRAINING_ANALYST;
use warehouse DBT_TRAINING_BI_WH;


-- ---------------------------------------------------------------------------
-- 1. The headline: totals for order 1028, and the line itself.
-- ---------------------------------------------------------------------------
select 
    order_line_id 
    , order_id 
    , item_name 
    , quantity 
    , unit_price_usd 
    , line_gross_revenue 
    , line_loaded_at
    
from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDER_LINES
where order_id = 1028
order by line_number
;

/* 
    BEFORE Day 3:   quantity 2, revenue 21.00, loaded 2026-03-02 
    AFTER Day 3:    quantity 5, revenue 52.50, loaded 2026-03-03 
    
    ONE row, both times. Not two. 
*/


-- ---------------------------------------------------------------------------
-- 2. The two facts that matter, in a single result.
-- ---------------------------------------------------------------------------
select 
    count(*) as total_line_count 
    , count(distinct order_line_id) as distinct_line_ids 
    , sum(line_gross_revenue) as total_revenue 
    , sum(
        case 
            when order_line_id = 10281 
                then line_gross_revenue 
            else 0 
        end
    ) as revenue_from_restated_line
from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDER_LINES
;

/* 
    total_line_count and distinct_line_ids must ALWAYS be equal. If they ever 
    diverge, the incremental strategy has appended a duplicate — and the 
    `unique` test on order_line_id in _marts__models.yml would already have 
    failed the build before you got here. 
    
    That is the difference between a warehouse that tells you it broke and one 
    that quietly produces a wrong number: the test exists. 
*/


-- ---------------------------------------------------------------------------
-- 3. Did the restatement propagate to the ORDER-level fact as well?
--
-- This is the subtle one. The order HEADER for 1028 never changed — only
-- its line did. An incremental model watermarking on the header's
-- loaded_at alone would never revisit this order, and fct_orders would
-- still show $21.00 while fct_order_lines showed $52.50.
--
-- The two facts would then disagree, and the singular test
-- assert_order_line_revenue_ties_to_orders would fail the build.
--
-- They agree because fct_orders watermarks on effective_loaded_at — the
-- LATER of the header's arrival and its lines'. See int_orders_with_lines.
-- ---------------------------------------------------------------------------
select 
    o.order_id 
    , o.order_date 
    , o.gross_revenue as order_level_revenue 
    , sum(l.line_gross_revenue) as sum_of_line_revenue 
    , o.gross_revenue - sum(l.line_gross_revenue) as difference 
    , o.order_loaded_at , o.lines_last_loaded_at 
    , o.effective_loaded_at
    
from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDERS o
join DBT_TRAINING_DB.DEV_MARTS.FCT_ORDER_LINES l 
    on o.order_key = l.order_key
where o.order_id = 1028
group by 1,2,3,6,7,8
;

/* 
    difference must be 0.00. 
    
    Look at the three timestamps on the right after Day 3: 
    
        order_loaded_at         2026-03-02      the header never changed 
        lines_last_loaded_at    2026-03-03      the line was corrected today 
        effective_loaded_at     2026-03-03      which is what the watermark uses 
        
    That third column is the only reason this order was rebuilt. 
*/


-- ---------------------------------------------------------------------------
-- 4. Every restated line in the warehouse.
--
-- A line whose loaded_at is later than its order's loaded_at has been
-- touched after the fact. In production this is a useful audit query —
-- "what changed under us since we last reported?"
-- ---------------------------------------------------------------------------
select 
    order_line_id 
    , order_id 
    , order_date 
    , item_name 
    , quantity 
    , line_gross_revenue 
    , order_loaded_at 
    , line_loaded_at 
    , datediff(
        'day', 
        date(order_loaded_at), 
        date(line_loaded_at)
    ) as days_between_order_and_correction
    
from DBT_TRAINING_DB.DEV_MARTS.FCT_ORDER_LINES
where line_loaded_at > order_loaded_at
order by line_loaded_at desc
;

/* 
    After Day 3, exactly one row: line 10281, corrected one day after the 
    order first arrived. 
*/
