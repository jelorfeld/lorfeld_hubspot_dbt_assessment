-- Business problem #3: listing 1303261 has a lockbox and a first aid kit, and
-- its longest possible stay is 159 days (expected result from the assessment brief).
-- Recomputed from fct_listing_day with a different gaps-and-islands method
-- (date minus row number) than analyses/final/longest_possible_stay_3.sql, so
-- the two implementations check each other. Returns a row only on a mismatch.

with available_days as (

    select
        listing_id,
        calendar_date,
        maximum_nights,
        calendar_date - cast(
            row_number() over (partition by listing_id order by calendar_date) as integer
        ) as island_key

    from {{ ref('fct_listing_day') }}

    where
        listing_id = 1303261
        and is_available
        and has_lockbox
        and has_first_aid_kit

),

stays as (

    select
        least(count(*), min(maximum_nights)) as possible_stay_days

    from available_days

    group by island_key

)

select max(possible_stay_days) as longest_stay_days

from stays

having max(possible_stay_days) is distinct from 159
