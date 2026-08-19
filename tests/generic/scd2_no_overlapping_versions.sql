{#- 
    ============================================================================ 
    scd2_no_overlapping_versions 
    ----------------------------------------------------------------------------
    Fails if any entity has two versions whose validity windows overlap. 
    
    THIS IS THE TEST THAT SAVES YOU. 
    
    A Type 2 dimension with overlapping windows does not throw an error, does 
    not look wrong, and does not fail any conventional test. `unique` on the 
    version key still passes. Row counts look plausible. Everything appears 
    fine. 
    
    What actually happens is that a point-in-time join matches TWO versions 
    for the affected instant, and every fact row joining through it is 
    duplicated. Revenue inflates by an amount that depends on how many 
    entities are affected and how much they traded — so it is not a round 
    number, not a constant percentage, and nearly impossible to spot by eye. 
    
    You find out when someone reconciles against the source system, which in 
    most organisations is a quarter later, and then you spend a fortnight
    explaining it. 
    
    dbt's snapshots will not produce this on their own. Hand-written SCD2 
    logic does it regularly, usually when the previous version's end date is 
    set with <= instead of <, or when a late-arriving change is inserted 
    without closing the record it supersedes. If you are migrating a 
    hand-built Type 2 dimension into dbt, run this test against the OLD table 
    first. It is frequently an uncomfortable morning. 
    
    ---------------------------------------------------------------------------- 
    HOW IT WORKS 
    A self-join of the dimension to itself on the same entity, excluding the 
    row matching itself, looking for any pair whose windows intersect. Two 
    ranges overlap when each starts before the other ends: 
    
        a.valid_from < b.valid_to AND b.valid_from < a.valid_to 
        
    Strictly less-than on both sides, because abutting windows (one ending 
    exactly where the next begins) are correct, not overlapping. 
    
    ---------------------------------------------------------------------------- 
    USAGE 
        data_tests: 
          - scd2_no_overlapping_versions: 
              entity_column: customer_id 
              valid_from_column: valid_from 
              valid_to_column: valid_to 
    ============================================================================
-#}

{% test scd2_no_overlapping_versions( 
        model, 
        entity_column, 
        valid_from_column='valid_from', 
        valid_to_column='valid_to' 
    ) 
%}

    with versions as ( 
        select 
                {{ entity_column }} as entity_id
            , {{ valid_from_column }} as valid_from 
            , {{ valid_to_column }} as valid_to 
            
        from {{ model }}
    ),

    overlaps as ( 
        select 
            a.entity_id 
            , a.valid_from as window_a_from 
            , a.valid_to as window_a_to 
            , b.valid_from as window_b_from 
            , b.valid_to as window_b_to 
            
        from versions a 
        inner join versions b 
            on a.entity_id = b.entity_id 
            -- a strict inequality on valid_from stops each pair being reported 
            -- twice, and stops a row matching itself 
            and a.valid_from < b.valid_from 
            -- the overlap condition 
            and a.valid_to > b.valid_from
            
    )

    select * from overlaps

{% endtest %}
