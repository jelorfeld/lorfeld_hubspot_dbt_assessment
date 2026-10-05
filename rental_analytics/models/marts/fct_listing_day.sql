with calendar as (

    select *
    from {{ ref('stg_calendar') }}

),

listings as (

    select *
    from {{ ref('stg_listings') }}

),

amenity_history as (

    select *
    from {{ ref('int_listing_amenity_history') }}

)

select
    c.listing_id,
    c.calendar_date,
    l.listing_name,
    l.host_id,
    l.neighborhood,
    l.property_type,
    l.room_type,
    l.accommodates,
    l.bedrooms,
    l.beds,
    c.nightly_price,
    c.is_available,
    c.reservation_id,
    c.minimum_nights,
    c.maximum_nights,
    h.amenities,
    h.valid_from_date as amenities_effective_from,
    h.has_air_conditioning,
    h.has_lockbox,
    h.has_first_aid_kit,
    l.listing_id is null as is_orphan_listing,
    c.reservation_id is not null as is_occupied,
    case
        when c.reservation_id is not null
            then c.nightly_price
        else 0
    end as nightly_revenue

from calendar as c

left join listings as l
    on c.listing_id = l.listing_id

left join amenity_history as h
    on
        c.listing_id = h.listing_id
        and c.calendar_date >= h.valid_from_date
        and (
            h.valid_to_date is null
            or c.calendar_date < h.valid_to_date
        )
