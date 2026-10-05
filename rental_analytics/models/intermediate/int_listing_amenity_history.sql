with changelog as (

    select
        listing_id,
        amenities_changed_at,
        amenities,
        cast(amenities_changed_at as date) as change_date

    from {{ ref('stg_amenities_changelog') }}

    where
        listing_id is not null
        and amenities_changed_at is not null

),

latest_change_per_day as (

    select
        listing_id,
        amenities_changed_at,
        amenities,
        change_date

    from (
        select
            *,
            row_number() over (
                partition by listing_id, change_date
                order by amenities_changed_at desc
            ) as row_num
        from changelog
    )

    where row_num = 1

),

effective_ranges as (

    select
        listing_id,

        change_date as valid_from_date,

        amenities,

        lead(change_date) over (
            partition by listing_id
            order by change_date
        ) as valid_to_date

    from latest_change_per_day

)

select
    listing_id,
    valid_from_date,
    valid_to_date,
    amenities,
-- did not pull out all amenities because some listings have a lot of amenities and it would be a pain to maintain. Instead, we will just pull out a few key amenities that we want to track over time.

{{ amenity_flag('amenities', 'Air conditioning') }}
as has_air_conditioning,

{{ amenity_flag('amenities', 'Lockbox') }}
as has_lockbox,

{{ amenity_flag('amenities', 'First aid kit') }}
as has_first_aid_kit

from effective_ranges
