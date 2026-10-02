select *
from {{ ref('stg_calendar') }}
where (listing_id, calendar_date) in (
    select
        listing_id,
        calendar_date
    from {{ ref('stg_calendar') }}
    group by 1, 2
    having count(*) > 1
)
order by listing_id, calendar_date
