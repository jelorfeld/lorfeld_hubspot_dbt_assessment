# lorfeld_hubspot_dbt_assessment
Analytics engineering technical assessment: dbt data pipeline and SQL analytical queries for rental property revenue, neighborhood pricing, and amenity changelogs.

**Contents:** [Setup](#setup) · [Metric definitions](#metric-definitions) · [Amenity history](#amenity-history-approach) · [Business results](#business-results) · [Data quality](#data-quality-strategy) · [Known limitations](#known-limitations) · [AI use](#ai-use-disclosure)

## Setup

The project runs locally on [DuckDB](https://duckdb.org/) and needs no warehouse credentials. Tested with Python 3.9 and dbt-core 1.10.

### 1. Install dependencies

From the repository root:

```bash
python3 -m venv .venv

cd rental_analytics
source ../.venv/bin/activate      # the venv lives at the repository root
pip install -r ../requirements.txt   # dbt-core, dbt-duckdb, sqlfluff
dbt deps                          # installs dbt_utils (packages.yml)
```

All later commands run from `rental_analytics/`. To reactivate the environment in a new shell, run `source ../.venv/bin/activate` from there.

### 2. Load the source data

The three source CSVs are in `rental_analytics/seeds/raw/` and load as dbt seeds. `dbt_project.yml` forces price and flag columns to `varchar`, so staging does all the parsing.

```bash
dbt seed
```

### 3. Build and test

```bash
dbt build
```

`dbt build` runs seeds, models and tests in dependency order, so step 2 is optional when running everything. `profiles.yml` is in the project folder, and dbt (1.3+) looks for it in the current directory, so no `--profiles-dir` flag is needed as long as you run commands from `rental_analytics/`.

**Expected result:** `PASS=51 WARN=4 ERROR=0`. Three of the warnings are one known orphan listing. The fourth lists the 2 raw listings rows that staging excludes. Both are explained in [Data quality](#data-quality-strategy).

### 4. Run the business-problem queries

The answers to the brief are dbt analyses in `analyses/final/`. Compile them, then run the compiled SQL against `dev.duckdb`:

```bash
dbt compile --select analyses/final
# compiled SQL: target/compiled/rental_analytics/analyses/final/*.sql
```

### 5. Inspect tables (and the DuckDB file lock)

DuckDB is an embedded, single-file database. Only one process can open `dev.duckdb` for writing at a time, and a write lock blocks every other connection. If a VS Code extension (a DuckDB explorer, SQLTools, dbt Power User, etc.) or a DuckDB CLI session has the file open, `dbt build` fails with:

```
IO Error: Could not set lock on file ".../dev.duckdb": Conflicting lock is held in ... Code Helper (Plugin) ...
```

The fix is to disconnect the other tool, or run "Developer: Restart Extension Host" in VS Code, and then build again. The reverse also applies: while dbt is building, viewers can't open the file.

Ways to look at the output without hitting the lock:

| Option | Command | Notes |
|---|---|---|
| `dbt show` | `dbt show --select fct_listing_day --limit 20` | Uses dbt's own connection, so it never conflicts. Also accepts `--inline "select ... from {{ ref('fct_listing_day') }}"` |
| DuckDB CLI, read-only | `duckdb -readonly dev.duckdb` | Good for ad-hoc SQL. Quit before running `dbt build` |
| VS Code extension, read-only | Set the connection's access mode to read-only | Keeps the schema browser. Disconnect before building, and reconnect afterwards to see new data |
| DuckDB UI | `duckdb -readonly -ui dev.duckdb` | Browser-based notebook (DuckDB 1.2.1+). Close before building |

To browse freely while building, copy the database after each build (`cp dev.duckdb browse.duckdb`) and point the viewer at the copy.

### Models and grain

| Model | Layer | Materialization | Grain | Rows |
|---|---|---|---|---|
| `stg_listings` | staging | view | One row per listing | 49 |
| `stg_calendar` | staging | view | One row per listing per calendar date | 18,250 |
| `stg_amenities_changelog` | staging | view | One row per listing per amenity-change event | 100 |
| `int_listing_amenity_history` | intermediate | view | One row per listing per effective-from date (type 2 history) | 100 |
| `fct_listing_day` | marts | table | One row per listing per calendar date | 18,250 |

**Materialization choices:**
- **Staging and intermediate are views:** they're cheap pass-through transforms with a single consumer, and views always reflect the latest seed load.
- **The mart is a table:** analysts query it directly and repeatedly.
- **Not incremental:** at this volume (18k rows) a full rebuild takes milliseconds, so incremental logic would add complexity for no gain. It becomes worth it once the calendar grows to many listings and years.

### What each layer does

- **Staging:** renames columns, casts types and cleans values. It parses `$1,125.00` prices and literal `'NULL'` text, maps `t`/`f` to booleans, and parses JSON arrays. It also removes rows that can't be keys: the blank-ID listing, the test listing, and duplicate calendar rows. No business logic or joins.
- **Intermediate:** turns the amenity changelog into effective-dated ranges and derives the amenity flags. See [Amenity history](#amenity-history-approach).
- **Marts:** `fct_listing_day` joins each calendar day to the listing's attributes and to the amenity configuration in effect on that date, and adds the revenue and occupancy measures.
- **Macros:** `amenity_flag` turns "does the amenity JSON array contain X" into one reusable expression, so adding a new amenity flag is one line.

## Metric definitions

All metrics come from `fct_listing_day`.

| Metric | Definition | How to aggregate |
|---|---|---|
| **Revenue** (`nightly_revenue`) | `nightly_price` on days with a reservation (`reservation_id is not null`), otherwise `0` | `sum(nightly_revenue)` |
| **Occupied day** (`is_occupied`) | The day has a reservation (`reservation_id is not null`) | `count_if(is_occupied)` |
| **Occupancy rate** | Occupied listing-days ÷ total listing-days in the period | `avg(is_occupied::int)`, or `count_if(is_occupied) / count(*)` |
| **Nightly price** (`nightly_price`) | The listed price for that date, **whether or not it was booked** | `avg(nightly_price)` describes listed prices, not revenue |
| **Reservations** | One reservation spans several rows | `count(distinct reservation_id)`, never `count(reservation_id)` |

**Revenue assumptions:**
- Revenue is the listed nightly price on booked nights.
- The source has no fees, taxes, discounts, cancellations or actual amounts paid.
- In this data, `is_available` is exactly the opposite of `is_occupied` (10,059 booked days, 8,191 open days). Owner-blocked days therefore can't be told apart from bookings, so occupancy uses all calendar days as the denominator.

### Common misuses to avoid

- **Comparing totals across partial months.** The calendar runs 2021-07-12 to 2022-07-11, so July 2021 has 20 days and July 2022 has 11. Use the occupancy rate or average daily revenue for period-over-period comparisons, or compare identical date ranges.
- **Using `nightly_price` as revenue.** It's populated on every day, including unbooked ones.
- **Counting reservations with `count(*)` or `count(reservation_id)`.** Both count booked nights, not reservations.
- **Dropping orphan rows by habit.** See [orphan handling](#how-they-appear-in-fct_listing_day).

## Amenity history approach

`amenities_changelog` records each listing's full amenity list as of each change. A listing's amenities can change over time, so a listing-day should be tagged with the amenities in effect **on that date**, not the current ones. Using current amenities would rewrite history: revenue from before an AC unit was installed would be counted as AC revenue.

`int_listing_amenity_history` is a type 2 slowly changing dimension:

1. **Collapse to one change per listing per day:** if a listing changed more than once on a date, the last change that day wins.
2. **Build effective ranges:** `valid_from_date` is the change date, and `valid_to_date` is the next change date (via `lead()`).
3. **Use half-open ranges:** `[valid_from_date, valid_to_date)`. A null `valid_to_date` marks the current configuration.
4. **Derive boolean flags** (`has_air_conditioning`, `has_lockbox`, `has_first_aid_kit`) with the `amenity_flag` macro.

`fct_listing_day` joins on `calendar_date >= valid_from_date and (valid_to_date is null or calendar_date < valid_to_date)`. Analysts get the amenities in effect on each day with no date logic of their own.

**How analysts query it:**
- **Amenity analysis over time:** filter or group on `has_*` flags directly.
- **Amenities not flagged:** `json_contains(amenities, '"Wifi"')`.
- **Current state:** use `valid_to_date is null` in the intermediate model.

**Alternatives considered:**
- *Current amenities only*, from the `listings` snapshot: simpler, but wrong for history, as described above.
- *dbt snapshots:* these capture changes going forward from when they're first run. The changelog already *is* the history, so it only needs reshaping, not capturing.
- *A wide table with one column per amenity:* rejected. The sample already has 81 distinct amenity strings and new ones appear freely in the source. The JSON array keeps every amenity queryable without a schema change. Flags exist only for amenities the business asks about.

**Tests:**
- Uniqueness on `listing_id` + `valid_from_date`.
- `valid_to_date > valid_from_date`.
- One current record per listing.
- A custom singular test, `tests/assert_no_overlapping_amenity_ranges.sql`. An overlap would duplicate rows in the mart and double-count revenue.

## Business results

Each query in `analyses/final/` reads only from `fct_listing_day`. The brief's expected results are also enforced as tests in `tests/business_results/` (see [validation](#business-results-validation)).

### #1 Amenity revenue: `amenity_revenue_1.sql`

Monthly revenue and share of revenue, split by whether the listing had air conditioning **on that date**. Result: 26 rows (13 months × 2 groups). Last two months:

| revenue_month | air_conditioning_status | total_revenue | revenue_percentage |
|---|---|---|---|
| 2022-06-01 | With air conditioning | 116,482.00 | 79.0 |
| 2022-06-01 | Without air conditioning | 31,042.00 | 21.0 |
| 2022-07-01 | With air conditioning | 40,157.00 | 78.8 |
| 2022-07-01 | Without air conditioning | **10,772.00** | **21.2** ✓ |

July 2022 covers only 11 days, so compare its percentages with other months, not its totals.

### #2 Neighborhood pricing: `neighborhood_pricing_2.sql`

Average change in nightly price per listing from 2021-07-12 to 2022-07-11, by neighborhood. Only listings with a price on both dates count. Result: 15 neighborhoods.

| neighborhood | average_price_increase | listings_with_both_prices |
|---|---|---|
| **Back Bay** | **44.00** ✓ | 1 |
| Charlestown | 21.80 | 5 |
| Downtown | 14.50 | 2 |
| Dorchester | 8.00 | 3 |
| … | … | … |
| South Boston | -25.00 | 2 |

### #3 Long stay / picky renter: `longest_possible_stay_3.sql`

For listings with **both** a lockbox and a first aid kit, the query finds the longest possible stay:
- It finds each unbroken run of available days (gaps and islands).
- It caps each run at the listing's `maximum_nights` (the strictest value within the run).
- It drops runs shorter than the listing's `minimum_nights` (again the strictest value), since they can't be booked at all. For 1303261 this removes one short window.
- It keeps each listing's longest run.

Result: 2 listings.

| listing_id | available_from | available_through | available_days | minimum_nights_required | maximum_nights_limit | possible_stay_days |
|---|---|---|---|---|---|---|
| **1303261** | 2022-02-03 | 2022-07-11 | 159 | 91 | 180 | **159** ✓ |
| 182613 | 2021-07-12 | 2021-10-31 | 112 | 91 | 1125 | 112 |

### Business results validation

| Problem | Expected (from brief) | Result | Test |
|---|---|---|---|
| #1 Amenity revenue | 21.2% of July 2022 revenue from listings without AC | 21.2% ($10,772 of $50,929) | `assert_july_2022_revenue_without_ac` |
| #2 Neighborhood pricing | Back Bay: one listing (10813), +$44 | +$44.00, 1 listing | `assert_back_bay_price_increase` |
| #3 Long stay | Listing 1303261: 159 days | 159 days | `assert_listing_1303261_longest_stay` |

**Design notes:**
- **Why test the mart and not the analysis files:** dbt tests can't `ref()` an analysis, so each test recomputes its result from `fct_listing_day`. The trade-off is some duplicated logic. The benefit is that each check is an independent implementation: the long-stay test uses a different gaps-and-islands method (date minus row number) than the analysis (lag plus running sum), so the two check each other.
- **How a failure reads:** each test returns a row only on a mismatch, showing the actual value it got.
- **Proof the tests can fail:** each test failed when its expected value was deliberately changed.
- **They are regression tests on the sample data.** In production, expected values like these would come from a reconciliation source rather than being hardcoded.

## Data quality strategy

### Source issues found

| Issue | Where | Handling |
|---|---|---|
| Two listings with a blank `ID` | `listings` | Removed in `stg_listings`: a row without a primary key can't be joined |
| One of those two is a test listing (`host_id = -99999`, `host_since` 1995, name "TESTING LISTING") | `listings` | Already removed by the blank-ID filter. A separate `host_id` filter is kept as a safeguard in case it ever arrives with a real ID |
| Calendar rows for listing `276450`, which isn't in `stg_listings` (365 rows) | `calendar` | **Kept** and flagged in the mart (see below) |
| Amenity changes for listing `276450` (2 rows) | `amenities_changelog` | **Kept**: it feeds `int_listing_amenity_history` |
| Duplicate `(listing_id, date)` key: listing `1303261` on 2022-07-07 appears 3 times | `calendar` | Deduplicated in `stg_calendar`; rows with a reservation are preferred so booked revenue is never dropped |
| Literal `'NULL'` text, `$` and `,` in price and ID fields | `calendar`, `listings` | Cleaned and cast in staging |

Rows filtered out in staging stay visible:

- `tests/assert_listings_excluded_from_staging.sql` (severity `warn`) returns the raw `listings` rows that staging drops. It warns with 2 rows today; a higher count means new bad rows have arrived in the source.
- `dbt_utils.accepted_range` (`min_value: 1`) on `stg_listings.host_id` fails the build if the test account or any non-positive host ID reaches staging.

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
- **Test severity:** the `relationships` tests use `warn_if: ">0"` with an `error_if` threshold set to the known orphan's row count (365 calendar rows, 2 changelog rows, 2 history rows). The one known defect warns without blocking the build, but a new orphan pushes the count over the threshold and fails it, instead of hiding inside the existing warning. The trade-off is that the thresholds are row counts: once `276450` is fixed upstream they should be lowered to `0`. A singular test that allows only `276450` would be the stricter alternative.

## Known limitations

### The data

- **Amenities don't change during the calendar window.**
  - All 100 changelog entries are dated 2008-12-03 to 2021-07-06, before the calendar starts on 2021-07-12. So in this sample every listing has one amenity configuration for the whole year.
  - The effective-dated join is still the right design, because it gives correct answers as soon as a change lands mid-window, but the sample doesn't exercise it.
  - The `amenities` column in `listings` matches each listing's latest changelog entry (same set, different order) for all 49 listings, so the two sources agree.
- **Listing attributes are current-state only** (type 1). Changes to neighborhood, room type or bedroom count over time are not tracked; only amenities have history.
- **Partial months at both ends:** July 2021 has 20 days and July 2022 has 11. See [Common misuses](#common-misuses-to-avoid).
- **The longest stay is limited by the calendar window.** Listing 1303261's 159-day window runs to the last calendar date, 2022-07-11, so its real availability may continue past it. The query reports the longest stay *within the data*.
- **Revenue is approximate:** listed price × booked nights. There's no fee, discount, tax or cancellation data.
- **Owner-blocked days can't be identified:** in this data, unavailable always means booked.

### The model

- **Day-level effective dates:** if a listing's amenities change more than once in a day, only the last change counts. Changes made partway through a day apply to the whole day.
- **No unknown-member row in the listing dimension:** orphan rows get null attributes rather than an `'Unknown'` label. That keeps the nulls honest, but `group by neighborhood` produces a `null` bucket that analysts need to know about.
- **Results #1–#3 are dbt analyses, not models,** so they aren't materialized for BI tools. If analysts need them regularly, monthly amenity revenue would be the first candidate to promote to a mart.

### The tooling

- **DuckDB allows only one writer at a time.** An IDE extension or CLI session holding `dev.duckdb` open blocks `dbt build`, and a running build blocks viewers. That's fine for a single-developer assessment but not for shared use: a team or BI tool would need a client-server warehouse (Snowflake, BigQuery, Postgres) or MotherDuck. See [Inspect tables](#5-inspect-tables-and-the-duckdb-file-lock) for workarounds.

## AI use disclosure

The assessment asks candidates to identify which parts of the work AI assisted with and how its output was checked.

**Tool:** Claude Code (Anthropic), used as a pair-programming assistant in the terminal.

AI use stayed within the assessment's four acceptable categories. Examples of each, with how I checked the output:

### Research best practices and syntax

1. **dbt 1.10 test syntax.**
   - *What AI did:* converted the tests in `int_listing_amenity_history.yml` to the `arguments:` block that dbt 1.10 expects.
   - *How I checked it:* `dbt build` parses and runs every test with no deprecation errors.
2. **Testing only some rows of a model.**
   - *What AI did:* showed how to scope generic tests with `config: where:`. This turns `unique` into "one current amenity record per listing" (`where valid_to_date is null`). It also limits `dbt_utils.expression_is_true` to closed ranges.
   - *How I checked it:* ran both tests against deliberately broken rows; each caught its case.

### Debug and optimize your code

1. **Tests that weren't running.**
   - *What AI did:* found that `int_listing_amenity_history.yml` was missing its `columns:` key. dbt was therefore ignoring every column test on the model, without any error.
   - *How I checked it:* after the fix, the 7 column tests that had been ignored show up in `dbt build` and pass.
2. **A wrong answer to Problem 1.**
   - *What AI did:* traced why the query returned 22.1% instead of the brief's 21.2%. The cause was an `is_orphan_listing = false` filter excluding listing `276450`. AI then found that this "orphan" is almost certainly the listing row with a blank ID.
   - *How I checked it:* re-ran the evidence queries myself (host date, opening price, amenity count) and confirmed that 21.2% comes back once the filter is removed.

### Generate documentation and comments

1. **This README.**
   - *What AI did:* drafted the setup, lineage, metric definitions, data-quality and limitations sections.
   - *How I checked it:* every figure was queried from `dev.duckdb`. That process caught one claim I corrected: the draft said there were "hundreds" of distinct amenities, and the real count is 81. I reviewed and edited the wording.
2. **Model docs and inline comments.**
   - *What AI did:* wrote the `fct_listing_day` and `is_orphan_listing` descriptions in `fct_listing_day.yml`. It also wrote the comments in `assert_no_overlapping_amenity_ranges.sql` (half-open ranges, and why an overlap would double-count revenue) and in `amenity_revenue_1.sql` (why orphans are included).
   - *How I checked it:* reviewed each one against what the SQL actually does.

### Explore alternative modeling approaches

1. **How to handle the orphan listing.**
   - *What AI did:* laid out three options with trade-offs:
     - recover the ID in staging,
     - keep the rows flagged and include them where valid,
     - exclude them everywhere.
   - *My decision:* keep the rows flagged and include them where valid. I chose this because the calendar is the record of revenue, and an inferred primary key shouldn't be hardcoded into staging.
2. **How to test the expected business results.**
   - *What AI did:* weighed moving the analysis logic into macros or models (testable directly, but harder to read) against recomputing each result from the mart.
   - *My decision:* recompute from the mart. For #3 the test uses a different gaps-and-islands method than the analysis, so the two implementations check each other.

### Repository cleanup

1. **Files that shouldn't be in version control.**
   - *What AI did:* audited the tracked files. It found that the Python virtual environment (`.venv/`, about 4,800 files and 134 MB) had been committed before `.gitignore` existed, so the ignore rule never applied to it. The same was true of the DuckDB build output, a dbt log, `.DS_Store` files, `.user.yml` and local VS Code settings. AI stopped tracking these files without deleting them locally, and added `requirements.txt` so the environment can be recreated.
   - *How I checked it:* `dbt build` still passes, and none of the 37 project files changed.
2. **Leftover scaffolding.**
   - *What AI did:* removed the dbt starter `.gitkeep` placeholders and the unused empty `snapshots/` folder, and fixed the `exolore/` → `explore/` folder typo along with the `.sqlfluffignore` path that pointed to it.
   - *How I checked it:* reviewed the list of changes before committing.

**What AI did not do:** generate the solution from the full assessment prompt, or make the core modeling decisions. I designed the layers, the listing-day grain and the type 2 amenity history. Where AI offered options (orphan handling, test approach), I made the final call, and I can explain and modify every model.
