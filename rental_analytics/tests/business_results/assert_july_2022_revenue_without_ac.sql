-- Business problem #1: 21.2% of July 2022 revenue came from listings without
-- air conditioning (expected result from the assessment brief).
-- Recomputed from fct_listing_day independently of
-- analyses/final/amenity_revenue_1.sql. Returns a row only on a mismatch.

with july_2022 as (

    select
        sum(nightly_revenue) filter (where not has_air_conditioning) as revenue_without_ac,
        sum(nightly_revenue) as total_revenue

    from {{ ref('fct_listing_day') }}

    where
        calendar_date >= date '2022-07-01'
        and calendar_date < date '2022-08-01'
        and has_air_conditioning is not null

)

select
    revenue_without_ac,
    total_revenue,
    round(100.0 * revenue_without_ac / total_revenue, 1) as pct_without_ac

from july_2022

where round(100.0 * revenue_without_ac / total_revenue, 1) is distinct from 21.2
