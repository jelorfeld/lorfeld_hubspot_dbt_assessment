with eligible_available_days as (

    select
        listing_id,
        calendar_date,
        minimum_nights,
        maximum_nights

    from {{ ref('fct_listing_day') }}

    where
        is_orphan_listing = false
        and has_lockbox = true
        and has_first_aid_kit = true
        and is_available = true

),

with_previous_date as (

    select
        *,
        lag(calendar_date) over (
            partition by listing_id
            order by calendar_date
        ) as previous_calendar_date

    from eligible_available_days

),

marked_windows as (

    select
        *,
        case
            when previous_calendar_date is null then 1
            when date_diff(
                'day',
                previous_calendar_date,
                calendar_date
            ) <> 1 then 1
            else 0
        end as starts_new_window

    from with_previous_date

),

numbered_windows as (

    select
        *,
        sum(starts_new_window) over (
            partition by listing_id
            order by calendar_date
            rows between unbounded preceding and current row
        ) as availability_window_id

    from marked_windows

),

availability_windows as (

    select
        listing_id,
        availability_window_id,
        min(calendar_date) as available_from,
        max(calendar_date) as available_through,
        count(*) as available_days,
        -- strictest owner rules within the window
        max(minimum_nights) as minimum_nights_required,
        min(maximum_nights) as maximum_nights_limit

    from numbered_windows

    group by
        listing_id,
        availability_window_id

),

constrained_windows as (

    select
        listing_id,
        available_from,
        available_through,
        available_days,
        minimum_nights_required,
        maximum_nights_limit,

        least(
            available_days,
            coalesce(maximum_nights_limit, available_days)
        ) as possible_stay_days

    from availability_windows

),

bookable_windows as (

    select *

    from constrained_windows

    -- a window shorter than the owner's minimum stay can't be booked at all
    where possible_stay_days >= coalesce(minimum_nights_required, 1)

)

select
    listing_id,
    available_from,
    available_through,
    available_days,
    minimum_nights_required,
    maximum_nights_limit,
    possible_stay_days

from bookable_windows

qualify
    row_number() over (
        partition by listing_id
        order by possible_stay_days desc, available_from asc
    ) = 1

order by
    possible_stay_days desc,
    listing_id asc
