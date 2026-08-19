{#- 
    ============================================================================ 
    unique_combination_of_columns 
    ---------------------------------------------------------------------------- 
    Fails if the combination of the given columns is not unique. 
    
    THE GRAIN TEST. Every fact and aggregate table has a declared grain — the 
    thing one row means — and this is how you stop that declaration from 
    being merely a comment. 
    
    agg_daily_truck_performance is "one row per truck per day". Nothing in the 
    SQL enforces that; a mistake in a join or a GROUP BY produces two rows for
    the same truck and day, every measure double-counts, and no built-in test 
    notices, because no single column is duplicated. 
    
    This is a hand-written equivalent of dbt_utils.unique_combination_of_columns, 
    and again the original is barely longer. Group by the columns, keep the 
    groups with more than one row. 
    
    ---------------------------------------------------------------------------- 
    A NOTE ON WHERE TO PUT IT 
    This is a MODEL-level test, not a column-level one, because it makes a 
    claim about a combination rather than about any single column. In the yml 
    it therefore sits under the model's own `data_tests:` key, at the same 
    indentation as `columns:` — not nested beneath a column. Getting that 
    wrong is the most common yml mistake in dbt, and the error message is not 
    especially helpful about it. 
    
    ---------------------------------------------------------------------------- 
    USAGE 
        data_tests: 
          - unique_combination_of_columns: 
              combination_of_columns: 
                - date_key 
                - truck_key 
    
    ============================================================================
-#}

{% test unique_combination_of_columns(model, combination_of_columns) %}

    {%- set column_list = combination_of_columns | join(', ') -%}
    
    select 
            {{ column_list }} 
        , count(*) as duplicate_row_count
    from {{ model }}
    group by {{ column_list }}
    having count(*) > 1
    
{% endtest %}
