-- Total revenue and occupied days in fct_listing_day must match stg_calendar.
-- The mart keeps every calendar row (including orphan listings), so any
-- difference means a join dropped or duplicated revenue.
-- Returns a row only on a mismatch.

with calendar_totals as (

    select
        sum(nightly_price) filter (where reservation_id is not null) as revenue,
        count(*) filter (where reservation_id is not null) as occupied_days

    from {{ ref('stg_calendar') }}

),

mart_totals as (

    select
        sum(nightly_revenue) as revenue,
        count(*) filter (where is_occupied) as occupied_days

    from {{ ref('fct_listing_day') }}

)

select
    c.revenue as calendar_revenue,
    m.revenue as mart_revenue,
    c.occupied_days as calendar_occupied_days,
    m.occupied_days as mart_occupied_days

from calendar_totals as c

cross join mart_totals as m

where
    c.revenue is distinct from m.revenue
    or c.occupied_days is distinct from m.occupied_days
