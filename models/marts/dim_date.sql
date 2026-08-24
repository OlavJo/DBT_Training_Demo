/* 
    dim_date 
    --------------------------------------------------------------------------- 
    A conventional calendar dimension. 
    
    It is built WITHOUT a package - dbt_utils.date_spine is the usual answer. 
    For teaching purposes, use Snowflake's own GENERATOR table function instead. 
    
        table(generator(rowcount => N)) 
        
    produces N rows of nothing, and seq4() numbers them 0..N-1. Add that to a 
    start date and you have a spine. 
    
    Range is fixed at 2026-2028, which comfortably covers the training data. 
    A production version would derive its bounds from the fact tables.
*/

with date_spine as ( 
    select 
        dateadd(day, seq4(), to_date('2026-01-01')) as date_day 
    from 
        table(generator(rowcount => 1096)) -- 2026-01-01 .. 2028-12-31
),

enriched as ( 
    select 
        -- surrogate key. Dates get an integer key by long convention: 
        -- 20260227 sorts correctly, reads at a glance, and joins cheaply. 
        to_number(to_char(date_day, 'YYYYMMDD')) as date_key 
        , date_day 
        
        -- calendar parts 
        , year(date_day) as year_number 
        , quarter(date_day) as quarter_number 
        , month(date_day) as month_number 
        , monthname(date_day) as month_name 
        , day(date_day) as day_of_month 
        , dayofweek(date_day) as day_of_week_number 
        , dayname(date_day) as day_of_week_name 
        , weekofyear(date_day) as week_of_year 
        
        -- useful groupings 
        , to_char(date_day, 'YYYY-MM') as year_month 
        , date_trunc('month', date_day) as month_start_date
        , last_day(date_day) as month_end_date 
        , date_trunc('quarter', date_day) as quarter_start_date 
        
        -- flags 
        , dayofweek(date_day) in (0, 6) as is_weekend 
        , date_day = current_date() as is_today 
        
    from date_spine
)

select * from enriched
