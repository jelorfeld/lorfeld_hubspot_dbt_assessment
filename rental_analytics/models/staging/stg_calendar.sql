with source as (

    select * from {{ ref('calendar') }}

),

cleansed as (

    select
        -- ids
        try_cast(listing_id as bigint) as listing_id,

        -- 'NULL' arrives as literal text in the source, so convert it to a real null
        try_cast(
            nullif(upper(trim(reservation_id)), 'NULL')
            as bigint
        ) as reservation_id,

        -- dates
        try_cast(date as date) as calendar_date,

        -- 't' / 'f' flag; any unexpected value becomes null and is caught by a not_null test
        case
            when lower(trim(available)) = 't' then true
            when lower(trim(available)) = 'f' then false
        end as is_available,

        -- price arrives as text like '$125.00'; it exists on every day, booked or not
        {{ clean_currency('price') }} as nightly_price,

        -- stay rules
        try_cast(minimum_nights as integer) as minimum_nights,
        try_cast(maximum_nights as integer) as maximum_nights

    from source

),

deduplicated as (

    select * from cleansed

    -- The source has at least one listing/date pair that appears twice.
    -- Keep one row per pair, preferring the row with a reservation so booked
    -- revenue is never dropped. Remaining ties are broken on price, then stay
    -- limits, so the result is deterministic.
    qualify row_number() over (
        partition by listing_id, calendar_date
        order by
            (reservation_id is not null) desc,
            nightly_price desc nulls last,
            minimum_nights asc,
            maximum_nights asc
    ) = 1

)

select * from deduplicated
