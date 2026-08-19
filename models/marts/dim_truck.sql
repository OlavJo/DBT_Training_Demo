/* 
    dim_truck 
    --------------------------------------------------------------------------- 
    One row per truck, current state. The Type 1 view, built from snap_truck. 
    
    Trucks are never erased from the source — retirement is a status change — 
    so is_current and is_latest_version always agree here, and the filter can 
    use either. is_current is used because it states the intent.
*/

with truck_scd as (
    select * from {{ ref('int_truck_scd') }}
),

locations as ( 
    select * from {{ ref('stg_locations') }}
),

current_version as ( 
    select * from truck_scd where is_current
),

final as ( 
    select 
    
            {{ generate_surrogate_key(['truck_id']) }} as truck_key 
        , current_version.truck_id 
        
        -- attributes 
        , current_version.truck_name 
        , current_version.make 
        , current_version.model 
        , current_version.model_year 
        , current_version.franchisee_name 
        , current_version.menu_type_id 
        , current_version.truck_status 
        , current_version.truck_status = 'ACTIVE' as is_active 
        
        -- home pitch, resolved. Truck 2 relocates 101 -> 104 on Day 2 and 
        -- this column follows it. 
        , current_version.primary_location_id 
        , locations.location_name as primary_location_name 
        , locations.city as primary_location_city 
        , locations.region as primary_location_region 
        
        -- lineage 
        , current_version.version_number as current_version_number 
        , current_version.valid_from as current_version_from 
        , current_version.source_updated_at 
        
    from current_version 
    left join locations 
        on current_version.primary_location_id = locations.location_id
)

select * from final
