{#- 
    ============================================================================ 
    scd2_exactly_one_current 
    ---------------------------------------------------------------------------- 
    Fails if any entity has zero, or more than one, current version. 
    
    The companion to scd2_no_overlapping_versions, and it catches the two 
    failure modes that test does not: 
    
        TWO CURRENT ROWS 
            Every "who are our GOLD customers?" query returns that customer 
            twice. Counts inflate. Joins fan out. Same silent duplication as 
            overlapping windows, arriving by a different route — usually a new 
            version inserted without closing the previous one. 
            
        ZERO CURRENT ROWS 
            The nastier one. The entity vanishes from every current-state 
            report while still existing perfectly well in the source. Nobody 
            notices a customer who is simply absent — there is no error, no 
            null, no obviously wrong number. Just quietly missing revenue. 
            Typically caused by a process that closed the old version and 
            failed partway before writing the new one. 
            
    Together these two tests are the complete correctness contract for a 
    Type 2 dimension: no gaps, no overlaps, exactly one row in force at any 
    moment. 
    
    ---------------------------------------------------------------------------- 
    THE `where` ARGUMENT 
    dbt passes a `where` config down to any generic test, and this project 
    uses it on dim_customer_history: 
    
        - scd2_exactly_one_current: 
            entity_column: customer_id 
            where: "not is_deleted_in_source" 
            
    Customer 5 is erased from the source on Day 3, so she correctly has NO
    current version afterwards. That is the whole point of 
    hard_deletes: invalidate. 
    
    Note what the `where` does here: it excludes the legitimately deleted 
    entities from the test rather than relaxing the rule for everyone. The 
    invariant stays strict for every entity it should apply to.  
    
    ---------------------------------------------------------------------------- 
    USAGE 
        data_tests: 
          - scd2_exactly_one_current: 
              entity_column: customer_id 
              is_current_column: is_current 
    ============================================================================
-#}

{% test scd2_exactly_one_current( 
        model, 
        entity_column, 
        is_current_column='is_current' 
    ) 
%}

    with version_counts as ( 
        select 
                {{ entity_column }} as entity_id 
            , sum(case when {{ is_current_column }} then 1 else 0 end)
                as current_version_count 
            , count(*) as total_version_count 
        from {{ model }} 
        group by 1
        
    )
    
    select 
        entity_id 
        , current_version_count 
        , total_version_count 
        , case 
            when current_version_count = 0 
                then 'NO current version' 
            else 'MULTIPLE current versions' 
        end as failure_reason
        
    from version_counts
    where current_version_count <> 1
    
{% endtest %}
