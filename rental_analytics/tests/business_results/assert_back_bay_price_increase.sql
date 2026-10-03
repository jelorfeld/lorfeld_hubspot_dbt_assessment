-- Business problem #2: Back Bay has a single listing (10813) whose price rose
-- $44 from 2021-07-12 to 2022-07-11 (expected result from the assessment brief).
-- Recomputed from fct_listing_day independently of
-- analyses/final/neighborhood_pricing_2.sql. Returns a row only on a mismatch.

with back_bay_prices as (

    select
        listing_id,
        max(nightly_price) filter (where calendar_date = date '2021-07-12') as start_price,
        max(nightly_price) filter (where calendar_date = date '2022-07-11') as end_price

    from {{ ref('fct_listing_day') }}

    where neighborhood = 'Back Bay'

    group by listing_id

),

neighborhood_average as (

    select
        count(*) as listing_count,
        list(listing_id) as listing_ids,
        avg(end_price - start_price) as avg_price_increase

    from back_bay_prices

)

select *

from neighborhood_average

where
    avg_price_increase is distinct from 44
    or listing_count != 1
    or listing_ids != [10813]
