{{ config(
    materialized='view',
    tags=['staging']
) }}

with source as (

    select *
    from {{ ref('calendar') }}

),

cleaned as (

    select
        try_cast(listing_id as bigint) as listing_id,

        try_cast(date as date) as calendar_date,

        case
            when lower(trim(available)) = 't' then true
            when lower(trim(available)) = 'f' then false
            else null
        end as is_available,

        try_cast(
            nullif(upper(trim(reservation_id)), 'NULL')
            as bigint
        ) as reservation_id,

        try_cast(
            nullif(
                nullif(
                    replace(replace(trim(price), '$', ''), ',', ''),
                    ''
                ),
                'NULL'
            )
            as decimal(10, 2)
        ) as nightly_price,

        try_cast(minimum_nights as integer) as minimum_nights,
        try_cast(maximum_nights as integer) as maximum_nights

    from source

)

select *
from cleaned