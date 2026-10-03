{% macro amenity_flag(amenities_column, amenity_name) %}

coalesce(
    json_contains(
        {{ amenities_column }},
        '"{{ amenity_name }}"'
    ),
    false
)

{% endmacro %}
