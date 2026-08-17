/*  =========================================================================== 
    02_day2_ingestion.sql "Day 2" — business date 2026-03-02 
    --------------------------------------------------------------------------- 
    RUN AS: DBT_TRAINING_INGEST 
    --------------------------------------------------------------------------- 
    Overnight, six things happened. Every one of them is deliberate, and every 
    one of them breaks a naive implementation: 
    
        1. Fifteen new orders for 2026-03-01.           ordinary incremental load 
        2. ONE LATE ORDER for 2026-02-28.               watermark on the right column 
        3. Customer 3 moved from Seattle to Denver.     SCD2, check strategy 
        4. Truck 2 changed its home location.           SCD2, timestamp strategy 
        5. Location 103 was renamed.                    Type 1 — history NOT kept 
        6. Menu item 7 went up in price.                historical prices unaffected 
        
    Read each change aloud before running it. The whole value of this exercise 
    is that the audience sees the cause, then sees the effect thirty seconds 
    later in the mart. 
    =========================================================================== */
    
USE ROLE DBT_TRAINING_INGEST;
USE WAREHOUSE DBT_TRAINING_WH;
USE SCHEMA DBT_TRAINING_DB.RAW;


/*  =========================================================================== 
    CHANGE 3 — Customer 3 has moved from Seattle to Denver 
    --------------------------------------------------------------------------- 
    Chloe Nguyen relocated. The source system overwrites her address in place: 
    there is now NO RECORD ANYWHERE that she ever lived in Seattle. 
    
    This is what operational systems do, and it is exactly the problem 
    snapshots exist to solve. Note also what this table does NOT have — an 
    UPDATED_AT column. The source gives us no way to know this row changed, 
    which is why snap_customer must use the `check` strategy and compare 
    column values rather than trusting a timestamp. 
    
    TIMELINE, because it matters for the attribution: 
        up to and including 2026-03-01      she is in Seattle and buys in Seattle 
        this batch (2026-03-02 06:00)       we learn she has moved 
        from 2026-03-02 onward              she buys in Denver (see day 3) 
        
    Her version 1 window therefore closes at 2026-03-02 06:00, which is the 
    _LOADED_AT stamped below. That is not an accident: snap_customer is 
    configured with `updated_at: loaded_at` precisely so its history lines up 
    with the simulated batch times rather than with the clock on the wall when 
    you happen to run this. See snapshots/snap_customer.yml. 
    =========================================================================== */
    
UPDATE CUSTOMER 
    SET 
        CITY = 'Denver', 
        POSTAL_CODE = '80205', 
        _LOADED_AT = '2026-03-02 06:00:00' 
    WHERE CUSTOMER_ID = 3;

   
/*  =========================================================================== 
    CHANGE 4 — Truck 2 has been reassigned to a different pitch 
    --------------------------------------------------------------------------- 
    Smoky Wheels moves from Pike Place Market (101) to Capitol Hill (104). 
    
    Contrast with the customer update above: this source system DOES maintain 
    UPDATED_AT, and maintains it honestly. That is why snap_truck can use the 
    cheaper `timestamp` strategy. Two sources, two strategies, and a real 
    reason for each. 
    =========================================================================== */
    
UPDATE TRUCK 
    SET 
        PRIMARY_LOCATION_ID = 104, 
        UPDATED_AT = '2026-03-01 20:00:00', 
        _LOADED_AT = '2026-03-02 06:00:00' 
    WHERE TRUCK_ID = 2;


/*  =========================================================================== 
    CHANGE 5 — Location 103 has been renamed 
    --------------------------------------------------------------------------- 
    "Denver Union Station" is now "Union Station Plaza". 
    
    We model LOCATION as a Type 1 dimension: the new name simply overwrites 
    the old one and no history is kept. That is a legitimate modelling choice, 
    not an oversight. Nobody analyses revenue by "what the pitch used to be 
    called". Compare with changes 3 and 4, where the previous value genuinely 
    matters — the decision to keep history is a business decision, made per 
    attribute, and it costs storage and complexity when you say yes. 
    =========================================================================== */
    
UPDATE LOCATION 
    SET 
        LOCATION_NAME = 'Union Station Plaza', 
        _LOADED_AT = '2026-03-02 06:00:00' 
    WHERE LOCATION_ID = 103;
    
    
/*  =========================================================================== 
    CHANGE 6 — Menu item 7 has gone up in price
    --------------------------------------------------------------------------- 
    The Kale Caesar Bowl rises from $9.00 to $10.50. 
    
    The dimension now shows $10.50. Every order line already in the warehouse 
    still carries the $9.00 it was actually sold at, because ORDER_LINE stores 
    the transaction price rather than looking it up. This is why fact tables 
    capture monetary values at the moment of the event instead of joining to 
    get them later — a lesson this audience already knows from Kimball, and a 
    good moment to point out that dbt changes none of it. 
    =========================================================================== */
    
UPDATE MENU_ITEM 
    SET 
        SALE_PRICE_USD = 10.50, 
        _LOADED_AT = '2026-03-02 06:00:00' 
    WHERE MENU_ITEM_ID = 7;
    
    
/*  =========================================================================== 
    CHANGE 1 — Fifteen new orders for 2026-03-01 
    --------------------------------------------------------------------------- 
    The ordinary case. Business date and load date differ by the usual one 
    overnight batch. 
    
    Two details to notice in passing: 
      * Order 1023 is at location 104 — Truck 2's NEW pitch. 
      * Orders 1024, 1032 and 1035 sell menu item 7 at the NEW $10.50 price, 
        while every earlier order line for that item still shows $9.00. 
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
    (1021, 1, 1, 101, '2026-03-01 08:20:00', 'WLKUP', 'COMPLETED', 'USD', 0.00, '2026-03-02 06:00:00'), 
    -- Customer 3 is still in Seattle today; the move is only picked up in 
    -- tomorrow's batch. Her last two Seattle purchases: 
    (1022, 4, 3, 102, '2026-03-01 09:10:00', 'MOB_APP', 'COMPLETED', 'USD', 0.00, '2026-03-02 06:00:00'), 
    (1023, 2, 2, 104, '2026-03-01 10:05:00', 'KIOSK', 'COMPLETED', 'USD', 0.00, '2026-03-02 06:00:00'), 
    (1024, 3, 6, 102, '2026-03-01 11:00:00', 'WEB', 'COMPLETED', 'USD', 0.00, '2026-03-02 06:00:00'), 
    (1025, 1, 4, 101, '2026-03-01 11:45:00', 'WLKUP', 'COMPLETED', 'USD', 0.00, '2026-03-02 06:00:00'), 
    (1026, 4, 5, 103, '2026-03-01 12:30:00', 'MOB_APP', 'COMPLETED', 'USD', 0.00, '2026-03-02 06:00:00'), 
    (1027, 2, 1, 104, '2026-03-01 13:15:00', 'KIOSK', 'COMPLETED', 'USD', 1.50, '2026-03-02 06:00:00'), 
    (1028, 3, 2, 102, '2026-03-01 14:00:00', 'WEB', 'COMPLETED', 'USD', 0.00, '2026-03-02 06:00:00'), 
    (1029, 1, 6, 101, '2026-03-01 15:20:00', 'WLKUP', 'COMPLETED', 'USD', 0.00, '2026-03-02 06:00:00'), 
    (1030, 4, 3, 102, '2026-03-01 16:10:00', 'MOB_APP', 'COMPLETED', 'USD', 0.00, '2026-03-02 06:00:00'), 
    (1031, 2, 4, 104, '2026-03-01 17:00:00', 'KIOSK', 'COMPLETED', 'USD', 0.00, '2026-03-02 06:00:00'), 
    (1032, 3, 1, 102, '2026-03-01 17:45:00', 'WEB', 'COMPLETED', 'USD', 0.00, '2026-03-02 06:00:00'), 
    (1033, 1, 2, 101, '2026-03-01 18:30:00', 'WLKUP', 'CANCELLED', 'USD', 0.00, '2026-03-02 06:00:00'), 
    (1034, 4, 5, 103, '2026-03-01 19:00:00', 'MOB_APP', 'COMPLETED', 'USD', 0.00, '2026-03-02 06:00:00'), 
    (1035, 3, 6, 102, '2026-03-01 19:40:00', 'KIOSK', 'COMPLETED', 'USD', 0.00, '2026-03-02 06:00:00')
    ;
    
INSERT INTO ORDER_LINE (
    ORDER_LINE_ID, 
    ORDER_ID, 
    MENU_ITEM_ID, 
    LINE_NUMBER, 
    QUANTITY, 
    UNIT_PRICE_USD, _
    LOADED_AT
) VALUES 
    (10211, 1021, 1, 1, 1, 7.50, '2026-03-02 06:00:00'), 
    (10212, 1021, 10, 2, 1, 6.50, '2026-03-02 06:00:00'), 
    (10221, 1022, 11, 1, 2, 8.00, '2026-03-02 06:00:00'), 
    (10231, 1023, 4, 1, 1, 11.00, '2026-03-02 06:00:00'), 
    (10232, 1023, 6, 2, 1, 6.50, '2026-03-02 06:00:00'),
    (10241, 1024, 7, 1, 1, 10.50, '2026-03-02 06:00:00'), 
    (10251, 1025, 2, 1, 1, 9.50, '2026-03-02 06:00:00'), 
    (10252, 1025, 3, 2, 1, 8.50, '2026-03-02 06:00:00'), 
    (10261, 1026, 12, 1, 2, 5.00, '2026-03-02 06:00:00'), 
    (10271, 1027, 5, 1, 1, 16.50, '2026-03-02 06:00:00'), 
    (10281, 1028, 8, 1, 2, 10.50, '2026-03-02 06:00:00'), 
    (10291, 1029, 1, 1, 2, 7.50, '2026-03-02 06:00:00'), 
    (10301, 1030, 10, 1, 2, 6.50, '2026-03-02 06:00:00'), 
    (10302, 1030, 12, 2, 1, 5.00, '2026-03-02 06:00:00'), 
    (10311, 1031, 6, 1, 3, 6.50, '2026-03-02 06:00:00'), 
    (10321, 1032, 9, 1, 1, 9.50, '2026-03-02 06:00:00'), 
    (10322, 1032, 7, 2, 1, 10.50, '2026-03-02 06:00:00'), 
    (10331, 1033, 2, 1, 1, 9.50, '2026-03-02 06:00:00'), 
    (10341, 1034, 11, 1, 1, 8.00, '2026-03-02 06:00:00'), 
    (10351, 1035, 7, 1, 2, 10.50, '2026-03-02 06:00:00')
    ;
    
    
/*  =========================================================================== 
    CHANGE 2 — THE LATE-ARRIVING ORDER 
    --------------------------------------------------------------------------- 
    This is the single most important row in the training project. 
    
    Order 1099 was placed at 19:30 on 2026-02-28. The payment terminal on that 
    truck lost connectivity and only synced two days later, so the row arrives 
    in the warehouse at 06:00 on 2026-03-02 — alongside today's batch. 
    
        ORDER_TS = 2026-02-28 19:30             the sale happened two days ago 
        _LOADED_AT = 2026-03-02 06:00           we are only learning about it now 
        
    Ask the room how they would pick up new rows incrementally. The natural 
    answer is "anything newer than the newest one I already have": 
    
        WHERE order_ts > (SELECT MAX(order_ts) FROM my_fact_table) 
        
    That filter is already at 2026-03-01 19:40 from today's batch, so this 
    order — a real $46 sale — is silently and permanently skipped. No error, 
    no warning, no failed test. Revenue for 2026-02-28 is simply wrong forever, 
    and nobody finds out until someone reconciles against the POS system. 
    
    Watermarking on _LOADED_AT instead picks it up correctly and files it 
    under the right business date. See models/marts/fct_orders.sql. 
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
    (1099, 4, 5, 103, '2026-02-28 19:30:00', 'WLKUP', 'COMPLETED', 'USD', 0.00, '2026-03-02 06:00:00')
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
    (10991, 1099, 5, 1, 2, 16.50, '2026-03-02 06:00:00'), 
    (10992, 1099, 6, 2, 2, 6.50, '2026-03-02 06:00:00')
    ;
    
    
/*  --------------------------------------------------------------------------- 
    VERIFY — what the source now looks like 
    --------------------------------------------------------------------------- */
    
SELECT 
    DATE(ORDER_TS) AS order_date, 
    COUNT(*) AS orders, 
    COUNT(DISTINCT DATE(_LOADED_AT)) AS distinct_load_dates,
    MAX(_LOADED_AT) AS latest_load
FROM ORDER_HEADER
GROUP BY 1
ORDER BY 1;

/* Expected: 
    2026-02-27      10 orders, 1 load date 
    2026-02-28      11 orders, 2 LOAD DATES <-- the late arrival 
    2026-03-01      15 orders, 1 load date 
    
    That "2" is the whole lesson, visible in a single cell. A business date 
    that was complete yesterday is not complete today. 
*/

/*  Customer 3 in the source: no trace of Seattle remains. */

SELECT 
    CUSTOMER_ID, 
    FIRST_NAME, 
    LAST_NAME, 
    CITY, 
    POSTAL_CODE, 
    LOYALTY_TIER
FROM CUSTOMER 
WHERE CUSTOMER_ID = 3;


/*  NEXT: run `dbt snapshot`, then `dbt build`, then the evidence queries in 
    analysis/. The snapshot must run FIRST — if you build the models before 
    snapshotting, the move to Denver is captured a run late and the 
    point-in-time attribution for today's orders will be wrong. */
