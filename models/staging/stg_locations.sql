/* 
    stg_locations 
    --------------------------------------------------------------------------- 
    One row per trading location. 
    
    There is no snapshot over this table, deliberately. Location 103 is renamed 
    on Day 2 and we simply let the new name overwrite the old one — a Type 1 
    dimension. 
    
    That is a business decision, not a technical shortcut. Nobody reports 
    revenue by "what the pitch used to be called", so paying the storage and 
    query complexity of history here would buy nothing. Keeping history is
    always available; the skill is knowing which attributes deserve it.
*/

with source as ( 
    select * from {{ source('tasty_bytes_raw', 'location') }}
),

renamed as (
 
    select 
        -- ids 
        location_id 
        
        -- attributes 
        , trim(location_name) as location_name 
        , trim(street) as street 
        , trim(city) as city 
        , trim(region) as region 
        , upper(trim(country)) as country 
        
        -- geo 
        , latitude 
        , longitude 
        
        -- audit
        , _loaded_at as loaded_at 
        
    from source
    
)

select * from renamed
