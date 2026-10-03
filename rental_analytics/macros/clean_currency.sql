{% macro clean_currency(column_name) %}

case
    when {{ column_name }} is null
        or upper(trim({{ column_name }})) in ('', 'NULL')
        then null
    else try_cast(
        replace(
            replace(trim({{ column_name }}), '$', ''),
            ',',
            ''
        ) as decimal(10, 2)
    )
end

{% endmacro %}
