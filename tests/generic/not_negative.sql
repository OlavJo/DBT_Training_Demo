{#- 
    ============================================================================ 
    not_negative 
    ---------------------------------------------------------------------------- 
    Fails if the column contains any value below zero. 
    
    THE ANATOMY OF A GENERIC TEST — this is the whole thing. 
    
    A dbt test is just a SELECT that returns the rows that are WRONG. 
    
      * zero rows returned      -> the test passes 
      * any rows returned       -> the test fails, and those rows are the evidence 
      
    That is the entire contract. `unique`, `not_null`, `accepted_values` and 
    `relationships` are built from exactly this pattern, and so is every test 
    in dbt_utils. Once you have seen it, writing your own stops feeling like 
    extending the framework and starts feeling like writing a WHERE clause. 
    
    The test macro block makes it reusable, taking `model` and `column_name` 
    which dbt supplies automatically from wherever the test is attached. 
    
    NULLS ARE NOT FAILURES HERE. `null < 0` is null, not true, so nulls pass. 
    That is deliberate: "must have a value" is not_null's job, and a test that 
    quietly enforces two rules at once is a test whose failure message lies to 
    you. One test, one claim. 
    ============================================================================
-#}

{% test not_negative(model, column_name) %}

    select 
        {{ column_name }} as failing_value 
        , count(*) as occurrences
    from {{ model }}
    where {{ column_name }} < 0
    group by 1
    
{% endtest %}
