-- Each listing must have at most one amenity configuration active on any date.
-- Ranges are half-open [valid_from_date, valid_to_date), and a null
-- valid_to_date means the range is still open. Two ranges overlap when each
-- one starts before the other ends.
--
-- An overlap would fan out fct_listing_day (one calendar row joining to two
-- amenity rows) and double-count revenue. Returns one row per overlapping pair.

with amenity_history as (

    select
        listing_id,
        valid_from_date,
        coalesce(valid_to_date, date '9999-12-31') as valid_to_date

    from {{ ref('int_listing_amenity_history') }}

)

select
    a.listing_id,
    a.valid_from_date as range_a_from,
    a.valid_to_date as range_a_to,
    b.valid_from_date as range_b_from,
    b.valid_to_date as range_b_to

from amenity_history as a

inner join amenity_history as b
    on
        a.listing_id = b.listing_id
        -- compare each pair once, and never a row with itself
        and a.valid_from_date < b.valid_from_date

where
    b.valid_from_date < a.valid_to_date
