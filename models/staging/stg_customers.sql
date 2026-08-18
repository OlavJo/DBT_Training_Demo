/* 
    stg_customers 
    --------------------------------------------------------------------------- 
    One row per customer, exactly as the source holds them right now. 
    
    STAGING RULES — the same six apply to every model in this folder: 
        1. One staging model per source table. No more, no fewer. 
        2. No joins. 
        3. No filtering of rows. 
        4. No aggregation. 
        5. Rename to the business vocabulary, cast types, tidy whitespace. 
        6. Materialised as a view, so it costs nothing to keep current. 
        
    Rule 2 is the one that gets broken. It would be trivial to join the 
    loyalty_tier_benefit seed here and carry the discount through. Resist it. 
    The moment staging joins, "where does this column come from?" stops having 
    a one-line answer, and the layer stops being a dependable mirror of the 
    source. Joins belong in intermediate/ — which is exactly why that folder 
    exists.
*/

with source as (
    select * from {{ source('tasty_bytes_raw', 'customer') }}
),

renamed as (
 
    select 
        -- ids 
        customer_id 
        -- attributes 
        , trim(first_name) as first_name 
        , trim(last_name) as last_name 
        , trim(first_name) || ' ' || trim(last_name) as full_name 
        , lower(trim(email)) as email 
        , trim(phone) as phone 
        
        -- location. Changes over time; snap_customer captures the history. 
        , trim(city) as city 
        , upper(trim(country)) as country 
        , trim(postal_code) as postal_code
        
        -- loyalty. Also changes over time. 
        , upper(trim(loyalty_tier)) as loyalty_tier 
        
        -- dates and flags 
        , sign_up_date 
        , marketing_opt_in 
        
        -- audit
        , _loaded_at as loaded_at 
    from source
)

select * from renamed
