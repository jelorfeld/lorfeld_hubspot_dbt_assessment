--Write a query to find the total revenue and percentage of revenue by month segmented by whether or not air conditioning exists on the listing.
with monthly_revenue as ( -- month, air conditioning status, total revenue

    select
        cast(date_trunc('month', calendar_date) as date) as revenue_month,

        case
            when has_air_conditioning = true
                then 'With air conditioning'
            when has_air_conditioning = false
                then 'Without air conditioning'
        end as air_conditioning_status,

        sum(nightly_revenue) as total_revenue

    from {{ ref('fct_listing_day') }}

    -- Orphan listings are intentionally included: their revenue comes from the
    -- calendar and their amenity flags from the changelog, so neither depends
    -- on the missing listing metadata. Excluding them would understate revenue.
    where has_air_conditioning is not null

    group by
        cast(date_trunc('month', calendar_date) as date),
        air_conditioning_status

),

with_percentages as ( -- month, air conditioning status, total revenue, monthly total revenue

    select
        revenue_month,
        air_conditioning_status,
        total_revenue,

        sum(total_revenue) over (
            partition by revenue_month
        ) as monthly_total_revenue

    from monthly_revenue

)

select
    revenue_month,
    air_conditioning_status,
    total_revenue,

    round(
        100.0 * total_revenue
        / nullif(monthly_total_revenue, 0),
        1
    ) as revenue_percentage

from with_percentages

order by
    revenue_month,
    air_conditioning_status
