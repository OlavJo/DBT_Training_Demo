/* 
    stg_trucks 
    --------------------------------------------------------------------------- 
    One row per food truck, as the source holds it now. 
    
    Note `updated_at` is carried through unchanged. snap_truck depends on it: 
    it is the column the `timestamp` snapshot strategy compares against to 
    decide whether a row has changed. 
    
    That is the difference between this model and stg_customers. Same shape, 
    same rules — but this source tells us when it changed and the customer 
    source does not, and that single fact determines which snapshot strategy 
    each one gets.
*/

with source as (
    select * from {{ source('tasty_bytes_raw', 'truck') }}
),

renamed as ( 

    select 
        -- ids 
        truck_id 
        , primary_location_id 
        , menu_type_id 
        
        -- attributes 
        , trim(truck_name) as truck_name 
        , trim(make) as make 
        , trim(model) as model 
        , year as model_year 
        , trim(franchisee_name) as franchisee_name 
        , upper(trim(truck_status)) as truck_status 
        
        -- source change tracking. Trusted — see snap_truck. 
        , updated_at 
        
        -- audit , 
        _loaded_at as loaded_at 
        
    from source
)

select * from renamed
