with source as (

    select * from {{ ref('listings') }}

),

renamed_and_cast as (

    select
        -- ids
        try_cast(id as bigint) as listing_id,
        try_cast(host_id as bigint) as host_id,

        -- strings (blank strings become nulls)
        nullif(trim(name), '') as listing_name,
        nullif(trim(host_name), '') as host_name,
        nullif(trim(host_location), '') as host_location,
        nullif(trim(neighborhood), '') as neighborhood,
        nullif(trim(property_type), '') as property_type,
        nullif(trim(room_type), '') as room_type,
        nullif(trim(bathrooms_text), '') as bathrooms_text,

        -- semi-structured (JSON arrays stored as text in the source)
        try_cast(host_verifications as json) as host_verifications,
        try_cast(amenities as json) as amenities,

        -- numerics
        try_cast(accommodates as integer) as accommodates,
        try_cast(bedrooms as decimal(10, 2)) as bedrooms,
        try_cast(beds as integer) as beds,
        try_cast(number_of_reviews as integer) as number_of_reviews,
        try_cast(review_scores_rating as decimal(5, 2)) as review_scores_rating,

        -- price arrives as text like '$1,125.00'; this is the snapshot price
        -- at the start of the calendar range, not a daily price
        {{ clean_currency('price') }} as listed_price,

        -- dates and timestamps
        try_cast(host_since as timestamp) as host_since,
        try_cast(first_review as date) as first_review,
        try_cast(last_review as date) as last_review

    from source

),

filtered as (

    select * from renamed_and_cast

    where
        -- Primary key is required. One real listing arrives with a blank ID
        -- and cannot be joined to calendar or changelog (see analyses/).
        listing_id is not null

        -- Test record: sentinel host_id of -99999, host_since in 1995.
        -- "is distinct from" keeps rows with a null host_id, which a
        -- plain "!=" would silently drop.
        and host_id is distinct from -99999

)

select * from filtered
