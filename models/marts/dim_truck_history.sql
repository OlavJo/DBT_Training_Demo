/* 
    dim_truck_history 
    --------------------------------------------------------------------------- 
    Full SCD Type 2 history for trucks. One row per truck per version. 
    
    Structurally identical to dim_customer_history — see that model for the 
    detailed commentary on validity windows and version-grain keys. 
    
    What this one answers that the customer history does not: 
    
        "Which pitch was truck 2 working from in February?" 
        "How long was truck 4 off the road?" 
        "What did each franchisee's revenue look like BEFORE the sale of 
        truck 1, and after?" 
        
    That last question is the one that tends to land with an operations 
    audience. Truck 1 changes franchisee on Day 3. Attribute its whole 
    history to the new owner and you have flattered them with three days of 
    someone else's takings.
*/

with truck_scd as ( 
    select * from {{ ref('int_truck_scd') }}
),

locations as ( 
    select * from {{ ref('stg_locations') }}
),

final as ( 
    select 
        -- version-grain key 
        -- Qualified for the same reason as dim_customer_history: `valid_from` 
        -- is also an alias further down this select, and they differ for 
        -- version 1. 
            {{ generate_surrogate_key(['truck_scd.truck_id', 'truck_scd.valid_from']) }} 
                as truck_history_key 
                
        -- link back to the current-state dimension 
            , {{ generate_surrogate_key(['truck_id']) }} as truck_key 
        , truck_scd.truck_id 
        
        -- attributes as they were during this window 
        , truck_scd.truck_name 
        , truck_scd.make 
        , truck_scd.model 
        , truck_scd.model_year 
        , truck_scd.franchisee_name 
        , truck_scd.menu_type_id 
        , truck_scd.truck_status 
        , truck_scd.primary_location_id 
        , locations.location_name as primary_location_name 
        , locations.city as primary_location_city 
        
        -- SCD2 mechanics , truck_scd.version_number 
        , truck_scd.effective_valid_from as valid_from 
        , truck_scd.valid_to , truck_scd.is_current 
        , truck_scd.source_updated_at 
        , datediff( 
            'day', 
            truck_scd.effective_valid_from, 
            least(truck_scd.valid_to, current_timestamp()::timestamp_ntz) 
        ) as version_duration_days 
        
    from truck_scd
    left join locations 
        on truck_scd.primary_location_id = locations.location_id
)

select * from final
