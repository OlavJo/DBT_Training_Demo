/* 
    dim_customer_history 
    --------------------------------------------------------------------------- 
    The full SCD Type 2 dimension. One row per customer PER VERSION. 
    
    Grain: customer_history_key — a hash of (customer_id, valid_from). 
    
    Familiar territory for anyone who has built a Type 2 dimension by hand. 
    The interesting part is not the shape but where it came from: this table 
    is derived, in its entirety, from a snapshot definition of about a dozen 
    lines. No merge statement, no version-closing logic, no "update the 
    previous row's end date" step to get subtly wrong. 
    
    HOW TO READ IT 
    --------------------------------------------------------------------------- 
    After Day 3, customer 3 has two rows: 
    
        version 1       Seattle     valid 1900-01-01 -> <Day 2 snapshot time> 
        version 2       Denver      valid <Day 2 snapshot time> -> 9999-12-31   CURRENT 
        
    Version 1's valid_from is backdated because the snapshot only started 
    watching on Day 1 — see int_customer_scd. Version 2's valid_to is the 
    far-future marker set by dbt_valid_to_current, so the windows are 
    contiguous and a point-in-time join needs no null handling. 
    
    Join it with:
    
        order_ts >= valid_from AND order_ts < valid_to 
        
    Note the asymmetry: >= on the lower bound, < on the upper. That is what 
    makes the windows abut without overlapping. Use <= on both and a sale 
    landing exactly on a boundary instant matches two versions and its 
    revenue is counted twice. 
    
    The scd2_no_overlapping_versions and scd2_exactly_one_current tests in 
    _marts__models.yml exist precisely to catch that class of error. They are 
    the tests that would actually save you in production.
*/

with customer_scd as ( 
    select * from {{ ref('int_customer_scd') }}
),

tiers as ( 
    select * from {{ ref('loyalty_tier_benefit') }}
),

final as ( 
    select 
        -- --------------------------------------------------------------- 
        -- Version-grain surrogate key. 
        -- The business key ALONE is not unique here — that is the whole 
        -- point of a Type 2 dimension — so the key must include the 
        -- validity start. This is the most common place to get a surrogate 
        -- key wrong, and the `unique` test below is what catches it. 
        -- --------------------------------------------------------------- 
        -- Qualified deliberately: `valid_from` is also the ALIAS of 
        -- effective_valid_from further down this same select, and the two 
        -- are different values for version 1. fct_order_lines hashes the 
        -- RAW valid_from, so this must too or the join silently returns 
        -- nothing. Qualifying the column makes the intent unambiguous. 
            {{ generate_surrogate_key(['customer_scd.customer_id', 'customer_scd.valid_from']) }}
                as customer_history_key 
                
        -- the Type 1 key, so a history row can be joined back to the 
        -- current-state dimension 
            , {{ generate_surrogate_key(['customer_id']) }} 
                as customer_key 
                
        -- natural key 
        , customer_scd.customer_id 
        
        -- attributes AS THEY WERE during this version's window 
        , customer_scd.first_name 
        , customer_scd.last_name 
        , customer_scd.full_name 
        , customer_scd.email 
        , customer_scd.phone 
        , customer_scd.city 
        , customer_scd.postal_code 
        , customer_scd.country 
        , customer_scd.loyalty_tier 
        , tiers.tier_rank as loyalty_tier_rank 
        , customer_scd.sign_up_date 
        , customer_scd.marketing_opt_in 
        
        -- --------------------------------------------------------------- 
        -- SCD2 mechanics, in business vocabulary. No dbt_* column reaches 
        -- this table. 
        -- --------------------------------------------------------------- 
        , customer_scd.version_number 
        , customer_scd.effective_valid_from as valid_from 
        , customer_scd.valid_to 
        , customer_scd.is_current 
        , customer_scd.is_latest_version 
        , customer_scd.is_deleted_in_source 
        
        -- how long this version was in force, in days. Handy for questions 
        -- like "how long do customers stay on BRONZE before upgrading?" 
        , datediff( 
            'day', 
            customer_scd.effective_valid_from,
            least(customer_scd.valid_to, current_timestamp()::timestamp_ntz) 
        ) as version_duration_days 
    
    from customer_scd 
    left join tiers 
        on customer_scd.loyalty_tier = tiers.loyalty_tier
)

select * from final
