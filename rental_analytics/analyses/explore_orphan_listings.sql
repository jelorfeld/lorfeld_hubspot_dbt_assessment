select
    'calendar' as source_table,
    c.listing_id,
    count(*) as row_count,
    min(c.calendar_date) as first_date,
    max(c.calendar_date) as last_date,
    count(c.reservation_id) as booked_days,
    sum(case when c.reservation_id is not null then c.nightly_price end) as booked_revenue
from {{ ref('stg_calendar') }} as c
left join {{ ref('stg_listings') }} as l
    on c.listing_id = l.listing_id
where l.listing_id is null
group by 1, 2

union all

select
    'changelog',
    a.listing_id,
    count(*),
    min(a.amenities_changed_at)::date,
    max(a.amenities_changed_at)::date,
    null,
    null
from {{ ref('stg_amenities_changelog') }} as a
left join {{ ref('stg_listings') }} as l
    on a.listing_id = l.listing_id
where l.listing_id is null
group by 1, 2
