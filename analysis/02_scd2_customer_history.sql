/* 
    =========================================================================== 
    EVIDENCE 02 — The SCD2 validity chain 
    --------------------------------------------------------------------------- 
    RUN AS: DBT_TRAINING_ANALYST 
    WHEN: After Day 1 (baseline), then again after Day 2 and Day 3. 
    --------------------------------------------------------------------------- 
    Watch customer 3 acquire a second version. 
    
        AFTER DAY 1 — one row, open-ended: 
            cust 3 v1 Seattle SILVER 1900-01-01 -> 9999-12-31 CURRENT 
            
        AFTER DAY 2 — the move to Denver is captured. Note the windows ABUT: v1's 
            valid_to is exactly v2's valid_from, so there is no gap and no overlap. 
            cust 3 v1 Seattle SILVER 1900-01-01 -> 2026-xx-xx 
            cust 3 v2 Denver SILVER 2026-xx-xx -> 9999-12-31 CURRENT 
            
        AFTER DAY 3 — customer 1 gains a version too (BRONZE -> GOLD), and 
            customer 5's final version is CLOSED without a successor, because she was 
            erased from the source. 
            
    The timestamps are the moment `dbt snapshot` RAN, not the moment the 
    business change happened. Snapshots know when they observed a change, not 
    when it occurred. If you need the latter, the source has to give it to you. 
    =========================================================================== 
*/

use role DBT_TRAINING_ANALYST;
use warehouse DBT_TRAINING_BI_WH;

-- ---------------------------------------------------------------------------
-- The full chain for every customer that has more than one version.
-- ---------------------------------------------------------------------------
select 
    customer_id 
    , version_number 
    , full_name 
    , city 
    , postal_code 
    , loyalty_tier 
    , valid_from 
    , valid_to 
    , is_current 
    , is_deleted_in_source 
    , version_duration_days
from DBT_TRAINING_DB.DEV_MARTS.DIM_CUSTOMER_HISTORY
where customer_id in ( 
    select customer_id 
    from DBT_TRAINING_DB.DEV_MARTS.DIM_CUSTOMER_HISTORY 
    group by customer_id 
    having count(*) > 1
)
order by 
    customer_id
    , version_number
;

/* 
    --------------------------------------------------------------------------- 
    The same thing for trucks — and a chance to point out that this history 
    came from a DIFFERENT snapshot strategy (timestamp rather than check), 
    configured in three lines, producing an identical shape. 
    --------------------------------------------------------------------------- 
*/
select 
    truck_id 
    , version_number 
    , truck_name 
    , primary_location_id 
    , primary_location_name
    , franchisee_name 
    , truck_status 
    , valid_from 
    , valid_to 
    , is_current
from DBT_TRAINING_DB.DEV_MARTS.DIM_TRUCK_HISTORY
order by 
    truck_id
    , version_number
;

/* 
    --------------------------------------------------------------------------- 
    WHAT THE SOURCE SYSTEM STILL KNOWS — run this one last, and let it sit. 
    
    The source has no memory of any of the above. Every prior value has been 
    overwritten. Everything in the two queries above exists ONLY because a 
    snapshot was running before the change happened. 
    
    This is the slide that makes the case: if you are not snapshotting today, 
    the history you will want next year is being destroyed right now, and no 
    amount of clever SQL will recover it afterwards. 
    --------------------------------------------------------------------------- 
*/
select 
    customer_id, 
    first_name, 
    last_name, 
    city, 
    postal_code, 
    loyalty_tier
from DBT_TRAINING_DB.RAW.CUSTOMER
order by 
    customer_id;
