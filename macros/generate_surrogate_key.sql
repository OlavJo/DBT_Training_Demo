{#- 
    ============================================================================ 
    generate_surrogate_key(field_list) 
    ---------------------------------------------------------------------------- 
    Builds a deterministic hash key from one or more columns. 
    
    This is a hand-written replacement for dbt_utils.generate_surrogate_key
    to showcase the simplicity of writing such a macro.

    Three important ideas in this macro:
    
        1. CAST EVERY FIELD TO VARCHAR. 
            Otherwise the hash of the number 1 and the hash of the string '1' 
            differ, and your keys stop matching across models the moment a 
            column's type changes upstream. 
            
        2. REPLACE NULLS WITH A SENTINEL. 
            concat_ws skips nulls, and md5(null) is null. Without the coalesce, 
            a row with a null component would get a null key — or worse, would
            collide with a different row whose columns happen to line up once 
            the null is dropped. 
            
        3. USE A SEPARATOR THAT CANNOT APPEAR IN THE DATA. 
            Without one, ('AB','C') and ('A','BC') produce the same string and 
            therefore the same key. '||' is unlikely in the columns of this 
            demo.
            
    ---------------------------------------------------------------------------- 
    WHY HASH KEYS RATHER THAN A SEQUENCE? 
    
    This is a trade-off, not a clear win either way.
    
    You lose: compact integers, natural insert ordering, and the ability to 
    tell at a glance which row arrived first. 
    
    You gain: determinism. The same business key produces the same surrogate 
    key on every environment, on every full refresh, forever. That is what 
    makes `dbt build --full-refresh` reproducible, lets dev and prod be 
    compared row for row, and means a rebuilt fact table still joins to a 
    dimension that was rebuilt separately. With a sequence, none of that 
    holds — rebuild the dimension and every key changes. 
    
    ---------------------------------------------------------------------------- 
    USAGE 
        {{ generate_surrogate_key(['order_id', 'line_number']) }} 
    ============================================================================
-#}

{% macro generate_surrogate_key(field_list) -%}

    {%- if field_list is string -%} 
        {%- set field_list = [field_list] -%} 
    {%- endif -%} 
    
    {%- set safe_fields = [] -%} 
    {%- for field in field_list -%}
        {%- do safe_fields.append( 
            "coalesce(cast(" ~ field ~ " as varchar), '_DBT_NULL_')" 
        ) -%} 
    {%- endfor -%} 
    
    md5(concat_ws('||', {{ safe_fields | join(', ') }}))
    
{%- endmacro %}
