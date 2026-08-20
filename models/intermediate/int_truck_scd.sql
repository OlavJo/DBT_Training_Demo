/* 
    int_truck_scd 
    --------------------------------------------------------------------------- 
    The truck equivalent of int_customer_scd. Same shape, same flags, same 
    reasoning — see that model for the full commentary. 
    
    The only structural difference: trucks are never hard-deleted from the 
    source (retirement is modelled as a status change, which is the better 
    choice), so there is no is_deleted_in_source flag here and is_current and 
    is_latest_version always agree. 
    
    That the two models are nearly identical is itself worth noticing. Once 
    the snapshot is configured, presenting a second Type 2 dimension is a 
    copy of a pattern, not a fresh piece of engineering. Compare with 
    maintaining two hand-written merge procedures that drifted apart over 
    three years because two different people touched them.
*/

with snapshotted as ( 
    select * from {{ ref('snap_truck') }}
),

versioned as ( 
    select 
        -- business key 
        truck_id 
        
        -- attributes as they were during this version's validity window 
        , trim(truck_name) as truck_name 
        , trim(make) as make 
        , trim(model) as model
        , year as model_year 
        , primary_location_id 
        , trim(franchisee_name) as franchisee_name 
        , menu_type_id 
        , upper(trim(truck_status)) as truck_status 
        
        -- the source's own change marker, carried through for reference 
        , updated_at as source_updated_at 
        
        -- dbt bookkeeping, renamed 
        , dbt_scd_id as truck_version_id 
        , dbt_valid_from as valid_from 
        , dbt_valid_to as valid_to 
        
        , row_number() over ( 
            partition by truck_id 
            order by dbt_valid_from 
        ) as version_number 
        
        , dbt_valid_to = to_timestamp_ntz('{{ var("scd_end_of_time") }} 00:00:00') 
            as is_current 
            
        , row_number() over ( 
            partition by truck_id 
            order by dbt_valid_from desc 
        ) = 1 as is_latest_version 
        
        -- Backdate the first version so that orders predating the first 
        -- `dbt snapshot` still resolve. See int_customer_scd for the full 
        -- explanation — it is the same gotcha and the same fix. 
        , case 
            when row_number() over ( 
                partition by truck_id order by dbt_valid_from 
                ) = 1 
                then to_timestamp_ntz('1900-01-01 00:00:00') 
            else dbt_valid_from 
        end as effective_valid_from 
        
    from snapshotted
)

select * from versioned
