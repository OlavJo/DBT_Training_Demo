/* 
    dim_customer 
    --------------------------------------------------------------------------- 
    One row per customer, showing their LATEST known state. The Type 1 view. 
    
    Use this to answer questions about customers as they are now: 
    
        "How many GOLD members do we have?" 
        "What is my Denver customer base worth?" 
        
    For questions about what was true at a point in the past, use 
    dim_customer_history instead. Both are published deliberately — see 
    evidence query 03, which runs the same revenue question through each and 
    gets two different, both-correct answers. 
    
    LATEST VERSION, NOT CURRENT VERSION — a deliberate choice 
    --------------------------------------------------------------------------- 
    This model filters on is_latest_version, not is_current. The two differ 
    for exactly one customer: number 5, erased from the source on Day 3. 
    
    Filtering on is_current would drop her row entirely, and every one of her 
    historical orders would then point at a customer key that no longer exists 
    in the dimension. The relationships test on fct_order_lines would fail, 
    and — worse — anyone joining fact to dimension would silently lose her 
    revenue from their totals. 
    
    So the key is retained, the row is flagged is_deleted_in_source, and 
    reporting can exclude her explicitly where that is appropriate. Erasure 
    applies to the personal attributes, not to the existence of the business 
    key; the books still have to balance. 
    
    (A production build would go further and null out or hash the name, email 
    and phone for erased customers while keeping the key and the aggregates. 
    That is a data-protection design question rather than a dbt one, and it is 
    left out here to keep the example readable.)
*/

with customer_scd as ( 
    select * from {{ ref('int_customer_scd') }}
),

tiers as ( 
    select * from {{ ref('loyalty_tier_benefit') }}
),

countries as ( 
    select * from {{ ref('country_region') }}
),

latest_version as ( 
    select * from customer_scd where is_latest_version
),

final as (
    select 
        -- --------------------------------------------------------------- 
        -- Surrogate key, hashed from the business key. See the macro for 
        -- why a hash rather than a sequence. 
        -- --------------------------------------------------------------- 
            {{ generate_surrogate_key(['customer_id']) }} as customer_key 
            
        -- natural key, always kept alongside for reconciliation to source 
        , latest_version.customer_id 
        
        -- attributes 
        , latest_version.first_name 
        , latest_version.last_name 
        , latest_version.full_name 
        , latest_version.email 
        , latest_version.phone 
        , latest_version.city 
        , latest_version.postal_code 
        , latest_version.country 
        , countries.region 
        , latest_version.sign_up_date 
        , latest_version.marketing_opt_in 
        
        -- loyalty, enriched from the seed 
        , latest_version.loyalty_tier 
        , tiers.tier_rank as loyalty_tier_rank 
        , tiers.discount_pct as loyalty_discount_pct 
            
        -- --------------------------------------------------------------- 
        -- Lineage and status flags. Publishing these on the dimension 
        -- means a business user can see how many times a record has 
        -- changed without needing access to the history table. 
        -- --------------------------------------------------------------- 
        , latest_version.version_number as current_version_number 
        , latest_version.valid_from as current_version_from 
        , latest_version.is_deleted_in_source 
    from latest_version 
    left join tiers 
        on latest_version.loyalty_tier = tiers.loyalty_tier 
    left join countries 
        on latest_version.country = countries.country
)

select * from final

