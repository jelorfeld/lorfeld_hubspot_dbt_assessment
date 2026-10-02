{{ config(
    materialized='view',
    tags=['staging']
) }}

with source as (

    select *
    from {{ ref('amenities_changelog') }}

),

cleaned as (

    select
        try_cast(listing_id as bigint) as listing_id,

        try_cast(change_at as timestamp) as amenities_changed_at,

        try_cast(
            nullif(trim(amenities), '')
            as json
        ) as amenities

    from source

)

select *
from cleaned
