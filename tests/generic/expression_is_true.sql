{#- 
    ============================================================================ 
    expression_is_true 
    ---------------------------------------------------------------------------- 
    Fails if the supplied SQL expression is not true for every row. 
    
    A minimal reimplementation of dbt_utils.expression_is_true. The original 
    is longer only because it handles more edge cases; the idea is exactly 
    this, and seeing that is worth more than importing it. 
    
    It is also the most useful test shape there is, because it turns any 
    business rule you can express in SQL into an enforced invariant:

        models: 
          - name: fct_orders 
            data_tests: 
              - expression_is_true: 
                  expression: "net_revenue <= gross_revenue" 
              - expression_is_true: 
                  expression: "line_count > 0" 
                  where: "order_date >= '2026-01-01'" 
                  
    The `where` argument narrows the test to a subset — useful when a rule 
    only became true from a certain date, which is a very common situation 
    in a warehouse that has been running for years. 
    
    Note the coalesce below. We want the rows where the expression is NOT 
    true, and in SQL that means two things: it evaluated to false, OR it 
    evaluated to null. Writing the obvious `where not (expression)` catches 
    only the first — a null expression is neither true nor false, so those 
    rows would slip through and the test would pass on data it never actually 
    checked. 
    
    `coalesce(expression, false) = false` treats null as a failure, which is 
    the right default for an assertion. If you genuinely want nulls to pass, 
    say so in the expression itself.
    
    ============================================================================
-#}

{% test expression_is_true(model, expression, where=None) %}

    select *
    from {{ model }}
    where coalesce(({{ expression }}), false) = false
    {% if where %} 
        and ({{ where }})
    {% endif %}
    
{% endtest %}
