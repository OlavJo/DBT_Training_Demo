{#- 
    ============================================================================ 
    create_semantic_view 
    ---------------------------------------------------------------------------- 
    Creates a Snowflake SEMANTIC VIEW over the finished star schema. 
    
    Run it with: 
        dbt run-operation create_semantic_view 
    
    A semantic view is NOT A TABLE OR A VIEW, so it is not one of dbt's 
    materializations and cannot be a model. 
    
    `run-operation` is dbt's hook into platform objects that dbt does not natively 
    model, but which still belong in the project, in version control, beside the 
    models they depend on. Row access policies, masking policies, tasks, 
    streams, alerts — all of them can live in macros and be applied from the 
    same repository as the models they are related to. 
    
    ---------------------------------------------------------------------------- 
    WHY THIS IS EASY 
    
    The semantic view below is almost trivial to write, and that is the whole 
    argument for the modelling work that preceded it. Every RELATIONSHIP maps 
    to a foreign key that already exists in fct_order_lines. Every DIMENSION 
    is already a clean, named, documented column on a conformed dimension. 
    Nothing needs to be reshaped, decoded or disambiguated here. 
    
    The semantic view is the payoff for the star schema built by dbt.
    ---------------------------------------------------------------------------- 
    FACTS vs METRICS
    
    FACTS are ROW-LEVEL expressions. `quantity * unit_price` for one line. 
    METRICS are AGGREGATIONS over facts. `SUM(...)` across many lines. 
    ============================================================================
-#}

{% macro create_semantic_view() %} 

    {%- set marts = target.schema ~ '_MARTS' -%} 
    {%- set view_name = target.database ~ '.' ~ marts ~ '.TASTY_BYTES_SALES' -%} 
    
    {{ log("Creating semantic view " ~ view_name, info=True) }} 
    
    {% set sql %}
    
        CREATE OR REPLACE SEMANTIC VIEW {{ view_name }} 
        
        TABLES ( 
            order_lines AS {{ target.database }}.{{ marts }}.FCT_ORDER_LINES 
                PRIMARY KEY (ORDER_LINE_KEY) 
                WITH SYNONYMS ('sales', 'line items', 'transactions') 
                COMMENT = 'One row per item sold. The grain of all sales analysis.', 
                
            customers AS {{ target.database }}.{{ marts }}.DIM_CUSTOMER 
                PRIMARY KEY (CUSTOMER_KEY)
                WITH SYNONYMS ('buyers', 'guests') 
                COMMENT = 'Current state of each customer.', 
                
            trucks AS {{ target.database }}.{{ marts }}.DIM_TRUCK 
                PRIMARY KEY (TRUCK_KEY) 
                WITH SYNONYMS ('food trucks', 'vans', 'fleet') 
                COMMENT = 'Current state of each food truck.', 
                
            menu_items AS {{ target.database }}.{{ marts }}.DIM_MENU_ITEM 
                PRIMARY KEY (MENU_ITEM_KEY) 
                WITH SYNONYMS ('products', 'dishes', 'menu') 
                COMMENT = 'Menu items available for sale.', 
                
            locations AS {{ target.database }}.{{ marts }}.DIM_LOCATION 
                PRIMARY KEY (LOCATION_KEY) 
                WITH SYNONYMS ('pitches', 'sites', 'venues') 
                COMMENT = 'Places where trucks trade.', 
                
            dates AS {{ target.database }}.{{ marts }}.DIM_DATE 
                PRIMARY KEY (DATE_KEY) 
                WITH SYNONYMS ('calendar', 'time') 
                COMMENT = 'Calendar dimension.' 
        ) 
        
        RELATIONSHIPS ( 
            lines_to_customers AS 
                order_lines (CUSTOMER_KEY) REFERENCES customers, 
                
            lines_to_trucks AS 
                order_lines (TRUCK_KEY) REFERENCES trucks, 
                
            lines_to_menu AS 
                order_lines (MENU_ITEM_KEY) REFERENCES menu_items, 
                
            lines_to_locations AS 
                order_lines (LOCATION_KEY) REFERENCES locations, 
                
            lines_to_dates AS 
                order_lines (DATE_KEY) REFERENCES dates 
        ) 
        
        FACTS ( 
            order_lines.gross_revenue AS LINE_GROSS_REVENUE 
                COMMENT = 'Revenue for one line: quantity x price at time of sale.', 
                
            order_lines.cogs AS LINE_COGS 
                COMMENT = 'Cost of goods for one line.', 
                
            order_lines.margin AS LINE_GROSS_MARGIN 
                COMMENT = 'Gross margin for one line.', 
                
            order_lines.units AS QUANTITY 
                COMMENT = 'Units sold on one line.' 
        ) 
        
        DIMENSIONS ( 
            customers.customer_name AS FULL_NAME 
                WITH SYNONYMS ('customer'), 
            
            customers.customer_city AS CITY 
                WITH SYNONYMS ('customer city', 'where the customer lives'), 
                
            customers.loyalty_tier AS LOYALTY_TIER 
                WITH SYNONYMS ('tier', 'membership level'), 
                
            customers.region AS REGION, 
            
            trucks.truck_name AS TRUCK_NAME 
                WITH SYNONYMS ('truck', 'van'), 
                
            trucks.franchisee AS FRANCHISEE_NAME 
                WITH SYNONYMS ('operator', 'owner'), 
                
            trucks.truck_status AS TRUCK_STATUS, 
            
            menu_items.item_name AS ITEM_NAME 
                WITH SYNONYMS ('product', 'dish'), 
                
            menu_items.item_category AS ITEM_CATEGORY 
                WITH SYNONYMS ('category', 'food type'), 
                
            menu_items.is_healthy AS IS_HEALTHY, 
            
            locations.location_name AS LOCATION_NAME 
                WITH SYNONYMS ('pitch', 'site'), 
                
            locations.trading_city AS CITY 
                WITH SYNONYMS ('trading city', 'location city'), 
                
            dates.order_date AS DATE_DAY 
                WITH SYNONYMS ('date', 'day'), 
                
            dates.month_name AS MONTH_NAME, 
            
            dates.day_of_week_name AS DAY_OF_WEEK_NAME 
                WITH SYNONYMS ('weekday'), 
                
            dates.is_weekend AS IS_WEEKEND,
            
            order_lines.order_channel AS ORDER_CHANNEL_NAME 
                WITH SYNONYMS ('channel', 'how it was ordered') 
                
        ) METRICS ( 
            order_lines.total_revenue AS SUM(order_lines.gross_revenue) 
                WITH SYNONYMS ('revenue', 'sales', 'turnover') 
                COMMENT = 'Total gross revenue from completed orders.', 
                
            order_lines.total_cogs AS SUM(order_lines.cogs) 
                COMMENT = 'Total cost of goods sold.', 
                
            order_lines.total_margin AS SUM(order_lines.margin) 
                WITH SYNONYMS ('profit', 'gross profit') 
                COMMENT = 'Total gross margin.', 
                
            order_lines.gross_margin_pct AS 
                SUM(order_lines.margin) 
                    / NULLIF(SUM(order_lines.gross_revenue), 0) 
                WITH SYNONYMS ('margin percent', 'profitability') 
                COMMENT = 'Gross margin as a fraction of revenue.', 
                
            order_lines.total_units AS SUM(order_lines.units) 
                WITH SYNONYMS ('units sold', 'items sold'), 
                
            order_lines.order_count AS COUNT(DISTINCT order_lines.ORDER_KEY) 
                WITH SYNONYMS ('orders', 'number of orders', 'transactions'), 
                
            order_lines.avg_order_value AS 
                SUM(order_lines.gross_revenue) 
                    / NULLIF(COUNT(DISTINCT order_lines.ORDER_KEY), 0) 
                WITH SYNONYMS ('AOV', 'average basket', 'average spend') 
                COMMENT = 'Average gross revenue per order.' 
        ) COMMENT = 'Tasty Bytes food truck sales. Training semantic model built over the dbt star schema.' 
        
    {% endset %} 
    
    {% do run_query(sql) %} 
    {{ log("Semantic view created: " ~ view_name, info=True) }} 
    
    {#- Make it usable by the consumer role. -#} 
    {% set grant_sql %} 
        GRANT SELECT ON SEMANTIC VIEW {{ view_name }} TO ROLE DBT_TRAINING_ANALYST; 
    {% endset %} 
    {% do run_query(grant_sql) %} 
    {{ log("Granted SELECT to DBT_TRAINING_ANALYST", info=True) }}
    
{% endmacro %}

{#- 
    ============================================================================ 
    drop_semantic_view — for teardown and for re-running the demo cleanly. 
        dbt run-operation drop_semantic_view 
    ============================================================================
-#}

{% macro drop_semantic_view() %} 

    {%- set marts = target.schema ~ '_MARTS' -%} 
    {%- set view_name = target.database ~ '.' ~ marts ~ '.TASTY_BYTES_SALES' -%} 
    {% set sql %} 
        DROP SEMANTIC VIEW IF EXISTS {{ view_name }}; 
    {% endset %} 
    {% do run_query(sql) %} 
    {{ log("Dropped semantic view " ~ view_name, info=True) }}
    
{% endmacro %}

