-- Finds listing/date pairs that appear more than once in the raw calendar.
-- Expected today: 3 rows, all for listing 1303261 on 2022-07-07 (identical copies).
-- stg_calendar removes these duplicates, so the same check on staging returns 0 rows.
--
-- Run from rental_analytics/:  dbt show --select explore_duplicate_calendar_keys

select *
from {{ ref('calendar') }}

qualify count(*) over (partition by listing_id, date) > 1

order by listing_id, date
