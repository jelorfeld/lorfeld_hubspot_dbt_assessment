--Write a query to find the average price increase for each neighborhood from July 12th 2021 to July 11th 2022.
with listing_prices as ( -- listing_id, neighborhood, price_on_2021_07_12, price_on_2022_07_11

    select
        listing_id,
        neighborhood,

        max(
            case
                when calendar_date = date '2021-07-12'
                    then nightly_price
            end
        ) as price_on_2021_07_12,

        max(
            case
                when calendar_date = date '2022-07-11'
                    then nightly_price
            end
        ) as price_on_2022_07_11

    from {{ ref('fct_listing_day') }}

    where
        is_orphan_listing = false
        and neighborhood is not null
        and calendar_date in (
            date '2021-07-12',
            date '2022-07-11'
        )

    group by
        listing_id,
        neighborhood

),

price_changes as ( -- shows the price increase for each listing that has both prices

    select
        listing_id,
        neighborhood,
        price_on_2021_07_12,
        price_on_2022_07_11,

        price_on_2022_07_11 - price_on_2021_07_12
            as price_increase

    from listing_prices

    where
        price_on_2021_07_12 is not null
        and price_on_2022_07_11 is not null

)

select
    neighborhood,
    round(avg(price_increase), 2) as average_price_increase,
    count(*) as listings_with_both_prices

from price_changes

group by neighborhood

order by average_price_increase desc
