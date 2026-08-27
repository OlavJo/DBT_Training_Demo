/*  =========================================================================== 
    03_day3_ingestion.sql "Day 3" — business date 2026-03-03 
    --------------------------------------------------------------------------- 
    RUN AS: DBT_TRAINING_INGEST 
    --------------------------------------------------------------------------- 
    Six more changes, each targeting a concept the first two days did not: 
    
        1. Thirteen new orders for 2026-03-02.          ordinary incremental load 
        2. A RESTATED ORDER LINE.                       merge vs append 
        3. Customer 1 upgraded to GOLD.                 SCD2 on a second attribute 
        4. Customer 5 ERASED from source.               hard-delete handling 
        5. Truck 4 into maintenance, Truck 1 sold.      SCD2, two attributes 
        6. A new customer and a new truck appear.       additions flow through 
        
    Dimension changes are applied before the orders, so that the new customer 
    and new truck exist before anything references them. 
    =========================================================================== */
    
USE ROLE DBT_TRAINING_INGEST;
USE WAREHOUSE DBT_TRAINING_WH;
USE SCHEMA DBT_TRAINING_DB.RAW;


/*  =========================================================================== 
    CHANGE 1 — Thirteen new orders for 2026-03-02 
    --------------------------------------------------------------------------- 
    Note who is NOT here: Truck 4 took no orders, because it went off the road. 
    And customer 5 places no orders, because she no longer exists — but her 
    earlier orders are still in the warehouse and must still be accounted for. 
    =========================================================================== */
    
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
    (1036, 1, 1, 101, '2026-03-02 08:15:00', 'WLKUP', 'COMPLETED', 'USD', 0.00, '2026-03-03 06:00:00'), 
    (1037, 5, 7, 105, '2026-03-02 09:00:00', 'MOB_APP', 'COMPLETED', 'USD', 0.00, '2026-03-03 06:00:00'), 
    (1038, 3, 2, 102, '2026-03-02 10:15:00', 'KIOSK', 'COMPLETED', 'USD', 0.00, '2026-03-03 06:00:00'), 
    (1039, 1, 4, 101, '2026-03-02 11:20:00', 'WEB', 'COMPLETED', 'USD', 0.00, '2026-03-03 06:00:00'), 
    (1040, 5, 3, 105, '2026-03-02 12:05:00', 'WLKUP', 'COMPLETED', 'USD', 0.00, '2026-03-03 06:00:00'), 
    (1041, 2, 6, 104, '2026-03-02 12:50:00', 'MOB_APP', 'COMPLETED', 'USD', 0.00, '2026-03-03 06:00:00'), 
    (1042, 3, 1, 102, '2026-03-02 13:35:00', 'KIOSK', 'COMPLETED', 'USD', 0.00, '2026-03-03 06:00:00'), 
    (1043, 5, 7, 105, '2026-03-02 14:20:00', 'WEB', 'COMPLETED', 'USD', 0.00, '2026-03-03 06:00:00'), 
    (1044, 1, 2, 101, '2026-03-02 15:10:00', 'WLKUP', 'COMPLETED', 'USD', 0.00, '2026-03-03 06:00:00'), 
    (1045, 2, 4, 104, '2026-03-02 16:00:00', 'MOB_APP', 'COMPLETED', 'USD', 0.00, '2026-03-03 06:00:00'), 
    (1046, 5, 3, 105, '2026-03-02 17:15:00', 'KIOSK', 'COMPLETED', 'USD', 0.00, '2026-03-03 06:00:00'), 
    (1047, 3, 6, 102, '2026-03-02 18:00:00', 'WEB', 'COMPLETED', 'USD', 0.00, '2026-03-03 06:00:00'), 
    (1048, 1, 7, 101, '2026-03-02 18:45:00', 'WLKUP', 'COMPLETED', 'USD', 0.00, '2026-03-03 06:00:00')
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
    (10361, 1036, 3, 1, 1, 8.50, '2026-03-03 06:00:00'), 
    (10371, 1037, 4, 1, 1, 11.00, '2026-03-03 06:00:00'), 
    (10372, 1037, 6, 2, 1, 6.50, '2026-03-03 06:00:00'), 
    (10381, 1038, 7, 1, 1, 10.50, '2026-03-03 06:00:00'), 
    (10391, 1039, 2, 1, 2, 9.50, '2026-03-03 06:00:00'), 
    (10401, 1040, 5, 1, 1, 16.50, '2026-03-03 06:00:00'), 
    (10411, 1041, 1, 1, 2, 7.50, '2026-03-03 06:00:00'), 
    (10412, 1041, 10, 2, 1, 6.50, '2026-03-03 06:00:00'), 
    (10421, 1042, 8, 1, 1, 10.50, '2026-03-03 06:00:00'), 
    (10431, 1043, 6, 1, 2, 6.50, '2026-03-03 06:00:00'), 
    (10441, 1044, 3, 1, 1, 8.50, '2026-03-03 06:00:00'), 
    (10442, 1044, 12, 2, 1, 5.00, '2026-03-03 06:00:00'), 
    (10451, 1045, 4, 1, 1, 11.00, '2026-03-03 06:00:00'), 
    (10461, 1046, 9, 1, 2, 9.50, '2026-03-03 06:00:00'), 
    (10471, 1047, 7, 1, 1, 10.50, '2026-03-03 06:00:00'), 
    (10472, 1047, 8, 2, 1, 10.50, '2026-03-03 06:00:00'), 
    (10481, 1048, 1, 1, 1, 7.50, '2026-03-03 06:00:00')
    ;
    
    
/*  =========================================================================== 
    CHANGE 2 — THE RESTATEMENT 
    ---------------------------------------------------------------------------  
    
    Order line 10281 (order 1028, placed 2026-03-01) was keyed in wrong. The 
    customer bought FIVE Quinoa Power Bowls, not two. The correction arrives 
    today, and the source system does what source systems do: it UPDATES the 
    existing row in place. Same key, new value, new load timestamp. 
    
        QUANTITY    2 -> 5                  at $10.50 each 
        revenue     $21.00 -> $52.50        a $31.50 correction  
    
    With `merge` and a `unique_key`, dbt updates the existing row in place: 
    
        fct_order_lines             row count:  UNCHANGED 
        total revenue:              UP by exactly $31.50  
    =========================================================================== */
    
UPDATE ORDER_LINE 
    SET 
        QUANTITY = 5, 
        _LOADED_AT = '2026-03-03 06:00:00' 
    WHERE ORDER_LINE_ID = 10281;

    
/*  =========================================================================== 
    CHANGE 3 — Customer 1 has been upgraded to GOLD 
    --------------------------------------------------------------------------- 
    Amara Osei crosses the spend threshold and moves BRONZE -> GOLD. 
    
    A second attribute, on a different customer, changing on a different day. 
    The snapshot handles it identically to the Denver move on Day 2. 
    =========================================================================== */
    
UPDATE CUSTOMER 
    SET 
        LOYALTY_TIER = 'GOLD', 
        _LOADED_AT = '2026-03-03 06:00:00' 
    WHERE CUSTOMER_ID = 1;
    
    
/*  =========================================================================== 
    CHANGE 4 — Customer 5 has been ERASED from the source system 
    --------------------------------------------------------------------------- 
    Elena Petrova exercised her right to erasure. The operational system does 
    what it is legally obliged to do: it deletes the row outright. 
    
    The row is simply GONE. Not flagged, not soft-deleted — absent. 
    
    Two things now have to be true at once, and they are in tension:
    
        (a) She must disappear from current customer reporting. 
        (b) Her past orders must still reconcile. Those sales happened, the 
        revenue is real, and the accounts must still balance. 
        
    `hard_deletes: invalidate` on the snapshot closes her final version rather 
    than losing it, which satisfies both. The dimension keeps the key so the 
    facts remain joinable, and the mart flags her as deleted in source. 
    
    NOTE: erasure applies to the personal attributes, not to the existence of 
    the business key. A dimension row that facts point at cannot simply 
    vanish — the correct answer is to:
        retain the key, 
        scrub or flag the attributes, and 
        keep the books balanced. 
    This is a modelling problem, and dbt does not solve it for you; it just 
    makes the history available to solve it WITH. 
    =========================================================================== */
    
DELETE FROM CUSTOMER WHERE CUSTOMER_ID = 5;


/*  =========================================================================== 
    CHANGE 5 — Truck 4 goes into maintenance; Truck 1 changes hands 
    --------------------------------------------------------------------------- 
    Le Petit Crepe (4) is off the road from today. Better Off Bread (1) has 
    been sold to a new franchisee. 
    
    Both bump UPDATED_AT, so snap_truck's timestamp strategy catches them. 
    Truck 4 takes no orders on 2026-03-02 — you will see it drop out of the 
    daily performance aggregate while remaining present in the dimension. 
    =========================================================================== */
    
UPDATE TRUCK 
    SET 
        TRUCK_STATUS = 'MAINTENANCE', 
        UPDATED_AT = '2026-03-02 21:30:00', 
        _LOADED_AT = '2026-03-03 06:00:00' 
    WHERE TRUCK_ID = 4;
    
UPDATE TRUCK 
    SET 
        FRANCHISEE_NAME = 'Cascade Street Food Group', 
        UPDATED_AT = '2026-03-02 22:15:00' , 
        _LOADED_AT = '2026-03-03 06:00:00' 
    WHERE TRUCK_ID = 1;
    
    
/*  =========================================================================== 
    CHANGE 6 — A new customer and a new truck 
    --------------------------------------------------------------------------- 
    Grace Lim signs up; Wok On Wheels enters service at RiNo Art District. 
    
    No backfill is needed, and both appear in the dimensions on the next run. 
    =========================================================================== */
    
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
    (7, 'Grace', 'Lim', 'grace.lim@example.com', '+1-303-555-0177', 'Denver',
        'US', '80205', 'BRONZE', '2026-03-02', TRUE, '2026-03-03 06:00:00')
    ;
    
INSERT INTO TRUCK (
    TRUCK_ID, 
    TRUCK_NAME, 
    MAKE, 
    MODEL, 
    YEAR, 
    PRIMARY_LOCATION_ID, 
    FRANCHISEE_NAME, 
    MENU_TYPE_ID, 
    TRUCK_STATUS, 
    UPDATED_AT, 
    _LOADED_AT
) VALUES 
    (5, 'Wok On Wheels', 'Chevrolet', 'P30', 2023, 105, 'Lim Enterprises', 2, 
        'ACTIVE', '2026-03-02 07:00:00', '2026-03-03 06:00:00')
    ;
    

    
/*  --------------------------------------------------------------------------- 
    VERIFY — what the source now looks like
    --------------------------------------------------------------------------- */
    
SELECT 
    'customers now in source' AS metric, 
    COUNT(*)::VARCHAR AS value 
FROM CUSTOMER
UNION ALL 
SELECT 
    'trucks now in source', 
    COUNT(*)::VARCHAR 
FROM TRUCK
UNION ALL 
SELECT 
    'orders now in source', 
    COUNT(*)::VARCHAR 
FROM ORDER_HEADER
UNION ALL 
SELECT 
    'order lines in source', 
    COUNT(*)::VARCHAR 
FROM ORDER_LINE
UNION ALL 
SELECT 
    'customer 5 still present?', 
    IFF(COUNT(*) = 0, 'NO - erased', 'yes')::VARCHAR 
FROM CUSTOMER 
WHERE CUSTOMER_ID = 5;

/* Expected: 
    customers now in source         6   (6 original - 1 erased + 1 new) 
    trucks now in source            5 
    orders now in source            49 
    order lines in source           71 
    customer 5 still present?       NO - erased 
*/


SELECT 
    DATE(ORDER_TS) AS order_date, 
    COUNT(*) AS orders, 
    COUNT(DISTINCT DATE(_LOADED_AT)) AS distinct_load_dates,
    MAX(_LOADED_AT) AS latest_load
FROM ORDER_HEADER
GROUP BY 1
ORDER BY 1;

/* Expected: ##TODO UPDATE! 
    2026-02-27      10 orders, 1 load date 
    2026-02-28      11 orders, 2 LOAD DATES <-- the late arrival 
    2026-03-01      15 orders, 1 load date 
    
    A business date that was complete yesterday is not complete today. 
*/

/*  The restated order line, as the source now holds it. */
SELECT 
    ORDER_LINE_ID, 
    ORDER_ID, 
    MENU_ITEM_ID, 
    QUANTITY, 
    UNIT_PRICE_USD, 
    QUANTITY * UNIT_PRICE_USD AS line_revenue, 
    _LOADED_AT
FROM ORDER_LINE 
WHERE ORDER_LINE_ID = 10281;


/* 
    This is what the customer table now looks like. 
    Note that customer 5 is gone, and customer 7 now appears,
    and customer 1 has been upgraded to GOLD loyalty tier.
*/
SELECT 
    *
FROM CUSTOMER;



/* 
    Truck 4 is in MAINTENANCE and Truck 1 has a new franchisee,
    and Truck 5 has arrived.
*/
SELECT
    *
FROM TRUCK;



/*
    NEXT STEPS: 

    1.  Issue the initial DBT commands: (The snapshot MUST run first, as the 
        dimas and facts are built on top)
            dbt snapshot
            dbt build
    2.  Explore the DB Catalog > DBT_TRAINING_DB > history dims and also the facts
    3.  Run 03_day3_post_dbt.sql
*/


