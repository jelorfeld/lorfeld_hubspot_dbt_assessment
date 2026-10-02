{{ config(
    materialized='view',
    tags=['staging']
) }}

with source as (
    select *
    from {{ ref('listings') }}
),
cleaned as (
    select
        try_cast(id as bigint) as listing_id,
        nullif(trim(name), '') as listing_name,
        try_cast(host_id as bigint) as host_id,
        nullif(trim(host_name), '') as host_name,
        try_cast(host_since as timestamp) as host_since,
        nullif(trim(host_location), '') as host_location,
        try_cast(host_verifications as json) as host_verifications,
        nullif(trim(neighborhood), '') as neighborhood,
        nullif(trim(property_type), '') as property_type,
        nullif(trim(room_type), '') as room_type,
        try_cast(accommodates as integer) as accommodates,
        nullif(trim(bathrooms_text), '') as bathrooms_text,
        try_cast(bedrooms as decimal(10, 2)) as bedrooms,
        try_cast(beds as decimal(10, 2)) as beds,
        try_cast(amenities as json) as amenities,
        try_cast(
            replace(replace(price, '$', ''), ',', '')
            as decimal(10, 2)
        ) as listed_price,
        try_cast(number_of_reviews as integer) as number_of_reviews,
        try_cast(first_review as date) as first_review,
        try_cast(last_review as date) as last_review,
        try_cast(review_scores_rating as decimal(5, 2))
            as review_scores_rating
    from source
)
select *
from cleaned