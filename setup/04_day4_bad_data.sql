/*  =========================================================================== 
    04_day4_bad_data.sql "Day 4" — OPTIONAL FAILURE DRILL 
    --------------------------------------------------------------------------- 
    RUN AS: DBT_TRAINING_INGEST 
    --------------------------------------------------------------------------- 
    Everything so far has worked. This script breaks the pipeline on purpose. 
    
    NOTE the difference between: 
    
        dbt run && dbt test             build everything, THEN check it 
        dbt build                       check as you go, and STOP on failure 
        
    With `run` then `test`, bad data propagates all the way to the marts, the 
    dashboards refresh, and the tests tell you afterwards — by which point the 
    wrong numbers have already been seen. 
    
    With `build`, dbt interleaves models and tests in dependency order. When a 
    test fails, everything DOWNSTREAM of it is SKIPPED. The bad data never 
    reaches the mart. The dashboard shows yesterday's numbers, which are 
    correct, instead of today's, which are not:
    
        "Stale but right" beats "fresh but wrong" 
        
    in almost every business context.
    =========================================================================== */
    
USE ROLE DBT_TRAINING_INGEST;
USE WAREHOUSE DBT_TRAINING_WH;
USE SCHEMA DBT_TRAINING_DB.RAW;


/*  --------------------------------------------------------------------------- 
    BREAKAGE 1 — an order line pointing at a menu item that does not exist. 
    
    Menu item 999 has never existed. This violates the `relationships` test on 
        stg_order_lines.menu_item_id. 
    
    Without the test, this row would sail through to fct_order_lines with a 
    null item_name, null category and — because the cost join fails — a 
    line_cogs of zero. Margin would be overstated by the full sale price and 
    nothing would look obviously wrong. 
    --------------------------------------------------------------------------- */
    
INSERT INTO ORDER_HEADER (
    ORDER_ID, 
    TRUCK_ID, 
    CUSTOMER_ID, 
    LOCATION_ID, 
    ORDER_TS, 
    ORDER_CHANNEL, 
    ORDER_STATUS, 
    ORDER_CURRENCY, 
    DISCOUNT_AMOUNT, 
    _LOADED_AT
) VALUES 
    (1050, 1, 1, 101, '2026-03-03 09:00:00', 'WLKUP', 'COMPLETED', 'USD', 0.00, '2026-03-04 06:00:00')
    ;
    
INSERT INTO ORDER_LINE (
    ORDER_LINE_ID, 
    ORDER_ID, 
    MENU_ITEM_ID, 
    LINE_NUMBER, 
    QUANTITY, 
    UNIT_PRICE_USD, 
    _LOADED_AT
) VALUES 
    (10501, 1050, 999, 1, 1, 12.00, '2026-03-04 06:00:00')
    ;
    
    
/*  --------------------------------------------------------------------------- 
    BREAKAGE 2 — a negative quantity. 
    
    A refund keyed as a sale, or a fat-fingered correction. Violates the 
    custom `not_negative` test on stg_order_lines.quantity. 
    
    This one is worth dwelling on because it is genuinely ambiguous. Negative 
    quantities are a perfectly reasonable way to represent returns in some 
    designs. The test encodes a DECISION — "in this warehouse, returns are not 
    modelled as negative sales lines" — and the failure is the warehouse 
    telling you the source has started doing something the model does not 
    expect. That is exactly what a test is for. 
    --------------------------------------------------------------------------- */
    
INSERT INTO ORDER_LINE (
    ORDER_LINE_ID, 
    ORDER_ID, 
    MENU_ITEM_ID, 
    LINE_NUMBER, 
    QUANTITY, 
    UNIT_PRICE_USD, 
    _LOADED_AT
) VALUES 
    (10502, 1050, 1, 2, -3, 7.50, '2026-03-04 06:00:00')
    ;
    

/*  --------------------------------------------------------------------------- 
    BREAKAGE 3 — a duplicated customer id. 
    
    The source system has produced two rows for customer 6. Violates `unique` 
    on stg_customers.customer_id. 
    
    This is the most dangerous of the three, because of what it does DOWNSTREAM 
    rather than in the row itself: the snapshot's unique_key is no longer 
    unique, so history for that customer becomes ambiguous, and every join 
    from a fact to the customer dimension FANS OUT and doubles revenue. 
    
    Note the test that catches it is on the STAGING model — as far upstream as 
    possible. Catching it here means the snapshot never sees it. Had the test 
    only existed on the mart, the snapshot would already have been corrupted 
    by the time it fired, and snapshots cannot be rebuilt. 
    --------------------------------------------------------------------------- */
    
INSERT INTO CUSTOMER (
    CUSTOMER_ID, 
    FIRST_NAME, 
    LAST_NAME, 
    EMAIL, 
    PHONE, 
    CITY, 
    COUNTRY, 
    POSTAL_CODE, 
    LOYALTY_TIER, 
    SIGN_UP_DATE, 
    MARKETING_OPT_IN, 
    _LOADED_AT
) VALUES 
    (6, 'Farid', 'Haddad', 'farid.haddad@example.com', '+1-206-555-0166', 'Seattle', 
        'US', '98104', 'SILVER', '2025-05-30', TRUE, '2026-03-04 06:00:00')
    ;
    
    
/*  =========================================================================== 
    NOW RUN: dbt build 
    
    Expected: several test FAILURES, and — the important part — a run summary 
    showing models SKIPPED. Those are the models that would have contained 
    wrong numbers. 
    
    Then: 
        dbt build --select stg_order_lines+         to see the blast radius 
        dbt retry                                   to resume after fixing 
        
    --------------------------------------------------------------------------- 
    TO FIX AND CONTINUE 
    --------------------------------------------------------------------------- */
    
/*
DELETE FROM ORDER_LINE WHERE ORDER_LINE_ID IN (10501, 10502);
DELETE FROM ORDER_HEADER WHERE ORDER_ID = 1050;
DELETE FROM CUSTOMER WHERE CUSTOMER_ID = 6 AND LOYALTY_TIER = 'SILVER';
*/


