# lorfeld_hubspot_dbt_assessment
Analytics engineering technical assessment: dbt data pipeline and SQL analytical queries for rental property revenue, neighborhood pricing, and amenity changelogs.

## Running the project

From `rental_analytics/`:

```bash
dbt deps
dbt build --profiles-dir .
```

Expected result: `PASS=34 WARN=3 ERROR=0`. The three warnings are known and explained below.

## Data quality strategy

### Source issues found

| Issue | Where | Handling |
|---|---|---|
| Test listing (`host_id = -99999`, `host_since` 1995, name "TESTING LISTING") | `listings` | Removed in `stg_listings` |
| Listing with a blank `ID` | `listings` | Removed in `stg_listings`: a row without a primary key can't be joined |
| Calendar rows for listing `276450`, which isn't in `stg_listings` (365 rows) | `calendar` | **Kept** and flagged in the mart (see below) |
| Amenity changes for listing `276450` (2 rows) | `amenities_changelog` | **Kept**: it feeds `int_listing_amenity_history` |
| Duplicate `(listing_id, date)` key: listing `1303261` on 2022-07-07 appears 3 times | `calendar` | Deduplicated in `stg_calendar`; rows with a reservation are preferred so booked revenue is never dropped |
| Literal `'NULL'` text, `$` and `,` in price and ID fields | `calendar`, `listings` | Cleaned and cast in staging |

### The orphan listing (the 3 warnings)

All three `relationships` warnings come from one listing ID, `276450`:

- `stg_calendar.listing_id` → 365 rows
- `stg_amenities_changelog.listing_id` → 2 rows
- `int_listing_amenity_history.listing_id` → 2 rows

**It's almost certainly the listing whose `ID` is blank in the source.** The blank-ID listing row (host `814298`, "19th Century Luxury | South End | 1BR 1BA #3") matches `276450` on three independent points:

- `host_since` is 2011-07-13, the same date as the listing's first amenity change.
- The listing price ($280.00) equals the calendar price on the first calendar day, 2021-07-12. That matches how `PRICE` is defined ("price as of the start of the date range in CALENDAR").
- Both have 28 amenities, the same count as the latest changelog entry.

I **deliberately did not hardcode `null → 276450` in staging**. The evidence is strong but circumstantial, and putting an inferred primary key into the model would hide the defect instead of fixing it. The source system should confirm the ID.

### Why the rows are kept

The calendar is the record of revenue and occupancy. The listing booked all 365 days for **$76,520**. The bookings are real; only the listing details are missing. Dropping them would make revenue and occupancy totals quietly disagree with the source. A wrong total is a worse failure than a missing neighborhood.

The listing is treated as an unknown dimension member: the fact row stays and the missing dimension is flagged.

### How they appear in `fct_listing_day`

- `is_orphan_listing = true` on all 365 rows.
- **Null:** listing attributes from `stg_listings`: `listing_name`, `host_id`, `neighborhood`, `property_type`, `room_type`, `accommodates`, `bedrooms`, `beds`.
- **Populated and valid:** calendar columns (`nightly_price`, `is_available`, `is_occupied`, `nightly_revenue`, `minimum_nights`, `maximum_nights`) and amenity columns from the changelog (`amenities`, `has_air_conditioning`, and so on).

**Guidance for analysts:** filter on `is_orphan_listing` only when the question needs listing attributes. Don't use it as a blanket exclusion. Grouping by `neighborhood` will show a `null` bucket for this listing on purpose, so the gap stays visible.

### Which analyses exclude them

| Analysis | Orphan rows | Why |
|---|---|---|
| #1 Amenity revenue | **Included** | Only needs revenue (calendar) and the AC flag (changelog), and both are valid. Excluding them gives 22.1% for July 2022 instead of the expected **21.2%**. |
| #2 Neighborhood pricing | Excluded | Needs `neighborhood`, which is null for orphans (`neighborhood is not null` filter). |
| #3 Longest stay | Excluded | Has an `is_orphan_listing = false` filter, which doesn't change the result: the listing has no lockbox or first aid kit and is never available. |

### In production: fix upstream or quarantine?

**Fix upstream; don't quarantine.**

- **Upstream:** raise it with the source-system owner, with the evidence above, so the blank `ID` gets fixed at the source. Once it's fixed, the listing joins normally and the warnings clear on their own.
- **Not quarantine:** moving these rows to a quarantine table would take real revenue out of the mart, which is the outcome the orphan flag exists to avoid.
- **Test severity:** keep the `relationships` tests at `warn` so one known defect doesn't block every build. To stop the known warning from hiding new problems, add `warn_if: ">0"` / `error_if` thresholds (or a singular test that allows only `276450`), so a new orphan listing fails the build instead of adding to the existing warning.
