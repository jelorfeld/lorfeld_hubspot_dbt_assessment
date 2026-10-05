-- Surfaces the raw listings rows that stg_listings filters out, so the
-- exclusions show up in every build rather than disappearing silently:
--   - a blank ID (no primary key, so the row can't be joined)
--   - the test account, sentinel HOST_ID = -99999
--
-- Expected today: 2 rows, and both have a blank ID. One is the test listing,
-- the other is a real listing (likely orphan 276450, see analyses/explore).
-- A higher count means new bad rows have arrived in the source.

{{ config(severity='warn') }}

select
    id as raw_id,
    host_id as raw_host_id,
    name as raw_name,
    case
        when try_cast(id as bigint) is null then 'blank ID'
        else 'test account (HOST_ID = -99999)'
    end as exclusion_reason

from {{ ref('listings') }}

where
    try_cast(id as bigint) is null
    or try_cast(host_id as bigint) = -99999
