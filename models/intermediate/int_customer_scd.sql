/* 
    int_customer_scd 
    --------------------------------------------------------------------------- 
    Turns the raw snapshot output into a clean, presentable SCD Type 2 history. 
    
    WHY THIS MODEL EXISTS 
    --------------------------------------------------------------------------- 
    Snapshot tables carry dbt's own bookkeeping columns — dbt_scd_id, 
    dbt_valid_from, dbt_valid_to, dbt_updated_at. Those are an implementation 
    detail of how dbt tracks history, and they should never reach a mart. 
    
    Two reasons that matters, and the second is the one that bites: 
    
        1. Nobody outside the data team knows what dbt_valid_to means, and a 
            column prefixed with a tool's name in a business-facing dimension is 
            a leak of implementation into the interface. 
            
        2. It couples your published dimensions to dbt's internals. When dbt 1.9 
        added dbt_valid_to_current and changed the default handling of these columns, 
        every downstream query referencing them directly was exposed to that change. 
        Renaming here means one model absorbs it. 
        
    This model is also where the derived flags every consumer needs are 
    computed once, correctly, rather than reimplemented in each dashboard.
    
    THE FOUR FLAGS 
    --------------------------------------------------------------------------- 
        version_number          1, 2, 3 ... in chronological order per customer 
        is_current              this version is the one in force RIGHT NOW 
        is_latest_version       this is the most recent version we ever saw 
        is_deleted_in_source    the customer has been erased from the source 
        
    is_current and is_latest_version are the same thing for every customer 
    EXCEPT one who has been deleted. Customer 5 is erased on Day 3: her final 
    version is the latest we ever saw, but it is not current, because she no 
    longer exists. Keeping the two flags separate is what lets dim_customer 
    retain her key — so her historical orders still join — while correctly 
    reporting that she is gone.
*/

with snapshotted as ( 
    select * from {{ ref('snap_customer') }}
),

versioned as ( 
    select 
        -- business key 
        customer_id 
        
        -- attributes as they were during this version's validity window 
        , first_name 
        , last_name 
        , trim(first_name) || ' ' || trim(last_name) as full_name 
        , lower(trim(email)) as email 
        , phone 
        , trim(city) as city 
        , upper(trim(country)) as country 
        , postal_code 
        , upper(trim(loyalty_tier)) as loyalty_tier 
        , sign_up_date 
        , marketing_opt_in 
        
        -- --------------------------------------------------------------- 
        -- dbt's bookkeeping, renamed into business vocabulary. 
        -- dbt_scd_id is already a hash of (customer_id, valid_from) and is 
        -- unique per version, so it makes a perfectly good version key. 
        -- --------------------------------------------------------------- 
        , dbt_scd_id as customer_version_id 
        , dbt_valid_from as valid_from 
        , dbt_valid_to as valid_to 
        
        -- chronological version number, 1 = the first we ever saw 
        , row_number() over ( 
            partition by customer_id 
            order by dbt_valid_from 
        ) as version_number 
        
        -- in force right now? dbt_valid_to_current gives current rows an 
        -- explicit far-future marker rather than NULL — see snap_customer. 
        , dbt_valid_to = to_timestamp_ntz('{{ var("scd_end_of_time") }} 00:00:00') 
            as is_current 
        
        -- the most recent version of this customer we ever recorded, whether 
        -- or not it is still in force 
        , row_number() over ( 
            partition by customer_id 
            order by dbt_valid_from desc 
        ) = 1 as is_latest_version 
        
    from snapshotted
),

with_deletion_flag as ( 
    select 
        versioned.* 
        
        -- If NO version of this customer is current, the customer has been 
        -- removed from the source system. See day 3, change 4. 
        , max(case when is_current then 1 else 0 end) over (partition by customer_id) = 0
            as is_deleted_in_source
            
        -- --------------------------------------------------------------- 
        -- effective_valid_from — the fix for a real snapshot gotcha 
        -- --------------------------------------------------------------- 
        -- A snapshot only knows history from the moment you FIRST RAN IT. 
        -- Version 1 of every customer has valid_from set to the timestamp 
        -- of that first `dbt snapshot`, not to when the customer actually 
        -- signed up. 
        -- 
        -- In this project the first snapshot runs on Day 1, but orders 
        -- already exist dated 2026-02-27 and 2026-02-28. A point-in-time 
        -- join using valid_from directly would find NO matching version for 
        -- any of them — every order placed before you started snapshotting 
        -- would silently lose its customer attributes. 
        -- 
        -- Backdating the first version to the beginning of time says 
        -- exactly what we mean: "this is the earliest state we know about, 
        -- and we assume it held for everything before it." That assumption 
        -- is not free — if a customer moved before Day 1 we will attribute 
        -- those old orders to the wrong city — but it is explicit, 
        -- documented, and vastly better than silently dropping the join. 
        -- 
        -- Worth flagging to anyone about to adopt snapshots: history starts 
        -- the day you start capturing it. There is no way to recover what 
        -- the source already overwrote. Start snapshotting earlier than you 
        -- think you need to. 
        -- --------------------------------------------------------------- 
        , case 
            when version_number = 1 
                then to_timestamp_ntz('1900-01-01 00:00:00') 
            else valid_from 
        end as effective_valid_from 
        
    from versioned
)

select * from with_deletion_flag
