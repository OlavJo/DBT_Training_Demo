/* 
    dim_location 
    --------------------------------------------------------------------------- 
    One row per trading location. TYPE 1 — no history is kept. 
    Location 103 is renamed from "Denver Union Station" to "Union Station 
    Plaza" on Day 2. After that run, the old name exists nowhere: not in the 
    source, not in a snapshot, not here. 
    
    That is the intended outcome, and the contrast with dim_customer_history 
    is the point. Both changes arrived in the same overnight batch. One is 
    remembered forever and one is forgotten immediately, because somebody 
    decided which attributes are worth the cost of remembering. 
    
    Keeping history is never free — it doubles the row count over time, 
    complicates every join, and forces every consumer to think about validity 
    windows. "Snapshot everything just in case" is a defensible instinct and 
    an expensive habit. Ask what question the history would answer, and if 
    nobody can name one, do this instead.
*/

with locations as ( 
    select * from {{ ref('stg_locations') }}
),

countries as ( 
    select * from {{ ref('country_region') }}
),

final as ( 
    select 
            {{ generate_surrogate_key(['location_id']) }} as location_key 
        , locations.location_id 
        
        , locations.location_name 
        , locations.street 
        , locations.city 
        , locations.region 
        , locations.country 
        , countries.region as reporting_region 
        , countries.currency_code as reporting_currency 
        , locations.latitude 
        , locations.longitude 
    from locations 
    left join countries 
        on locations.country = countries.country
)

select * from final
