with monthly_revenue as (

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

    where
        is_orphan_listing = false
        and has_air_conditioning is not null

    group by
        cast(date_trunc('month', calendar_date) as date),
        air_conditioning_status

),

with_percentages as (

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
