# Earthquake Policy Simulation — Ashkelon/Tiberias ABM

## Purpose

This is a MATLAB agent-based model (ABM) simulating a city's housing, labor, and
business markets before and after an earthquake, used to test the effect of
different post-disaster policy choices — where displaced households shelter,
how quickly buildings get rebuilt, how the local economy absorbs the shock —
on recovery outcomes over time.

**Main run script:** [`run_model_earthquake_shelteroverflow.m`](run_model_earthquake_shelteroverflow.m).
Set `city` (`'Ashkelon'`, `'Tiberias'`, or `'Jerusalem'` — see Data section)
and `shock_step` before calling `run()`; a per-SA damage table must exist at
`[file,'earthquake_damage.csv']` for whichever city is selected. Ashkelon,
Tiberias, and Jerusalem all now have calibrated `commute_outside`/
`alfa`/`beta`/`lamda`/`delta` constants (Jerusalem's `commute_outside` is a
best-available data-driven placeholder, not independently cross-validated
the way Ashkelon/Tiberias's are — see the city configuration block's own
comment). Ready-made per-city driver scripts exist for the validated
calibrations: [`run_tiberias_calibrated.m`](run_tiberias_calibrated.m),
[`run_jerusalem_calibrated.m`](run_jerusalem_calibrated.m).

`run_model_earthquake.m` is an earlier, simpler variant without the
out-of-city overflow tier (see Policies section) — kept for reference, not
actively maintained in parallel with the main script.

---

## Data

### Data required to run the model directly

Each city needs a compiled `.mat` dataset (e.g. `data_for_model_Ash2hotels.mat`,
`data_for_model_TVR_hotels.mat`) containing `Assets`, `Build_Data`, `HH_data`,
`Individuals_data`, `Work_places` (plus their `_P`/`_p` header-name
companions), and a `sas_national.xlsx` (15-column raw layout) and
`commuting.xlsx` in that city's data folder. A per-SA `earthquake_damage.csv`
(columns `SAID`, `dmg_prc`) is required to actually trigger a shock.

Both Ashkelon and Tiberias now have hotel buildings tagged (usage=7) as a
shelter type: `identify_hotels_TVR.m` (39 buildings, Tiberias) and
[`identify_hotels_ASH.m`](identify_hotels_ASH.m) (3 buildings, matched by
real-world coordinates via [`wgs84_to_itm.m`](wgs84_to_itm.m)). Use the
`...hotels` variant of each city's dataset
(`data_for_model_Ash2hotels.mat`/`data_for_model_TVR_hotels.mat`), not the
plain one — drop-in replacement, identical except for the hotel tagging.

Ashkelon's `ASH22\sas_national.xlsx` was previously a different 5-column
pre-summarized format, incompatible with `read_sas_data.m`'s hardcoded
15-column layout — it's now been replaced with the correctly-formatted,
Ashkelon-specific content (originally `sas_national1.xlsx`); the old
incompatible file is preserved at
`ASH22/sas_national_5col_incompatible_backup.xlsx` for reference. Since that
table doesn't cover every SA Ashkelon's `Build_Data` references, a per-city
backfill (donor-row copy from a random existing SA) runs at load time in
`run_model_earthquake_shelteroverflow.m` for any missing rows — see that
block's comment for why this is a per-city choice, not a general fallback in
`read_sas_data.m` itself.

### Data required to build a new city's dataset (`data_allocation/`)

[`main_alloc.m`](data_allocation/main_alloc.m) runs the full pipeline from raw
survey/cadastral data to a model-ready `.mat` file:

1. Raw inputs needed in the city's folder: `bldgs_with_tt.csv`, `assets.csv`,
   `dealData.csv`, `model parameters.csv`.
2. `start_spatial_dataupdate.m` → `buildings&assets.mat`
3. `start_HH_2018up.m` → `HH_&_ind_data.mat`
4. `distribute_HH_2019.m` → `data_after_lur.mat`
5. `create_work_place.m` → `data_after_working_place.mat`
6. `distribute_workers.m` → final named output (e.g. `data_for_model_JER.mat`)

Ashkelon, Tiberias, and Jerusalem have complete, working compiled datasets.
Arad is configured as a city option but has no compiled `.mat` yet (see
Untested/Outstanding section).

### Validating a city's allocation output, and the Jerusalem fix history

`data_allocation/validate_allocation.py` / `plot_allocation.py` check a
compiled city's synthetic population against the census data it was built
from — structural consistency (duplicate IDs, orphaned records, negative
prices), demographics (age/household-size/elderly shares), income deciles,
car ownership, and labor-force participation/commuting shares. City-agnostic:
`python validate_allocation.py --city JER` derives all paths (`.mat`, census
CSV, report output) from the city name. Full usage and how to interpret a
FAIL: [`data_allocation/VALIDATION_AND_FIXES.md`](data_allocation/VALIDATION_AND_FIXES.md).

Bringing Jerusalem to a clean validation state (12 FAILs → 0) surfaced four
real code bugs, now fixed for every city using this pipeline, plus one
corrupted census input file:

- **`create_HH_12_2018.m`** — elderly-household count was being recomputed
  from a raw population headcount partway through the function (dividing by
  100 and multiplying by SA population inflated it ~10x), overriding the
  correct, earlier household-based estimate and badly over-assigning elderly
  status (38% vs. census 27%).
- **`start_HH_2018up.m`** — Jerusalem's census extract has `comm31`/`comm34`
  (metro-zone commuting shares) completely empty for every SA, which the
  generic NaN-fill can't repair (mean of all-NaN is NaN). Added an explicit
  derivation: `comm31 = 1 - comm99`, `comm34 = 0`.
- **`distribute_workers.m`** — before the fix above, a NaN commuting target
  was silently treated as "the entire remaining worker pool" instead of 0
  (MATLAB's `min` ignores NaN), so 100% of workers ended up local instead of
  the real ~87%/13% split, and a second, independent bug in the fallback
  assignment branch could request more workplace assignments than remained
  in the pool. Fixed with an explicit NaN-to-zero fallback and a
  `min(length(B),length(F))` cap.
- **`labor_datasample.m`** — "currently working" status was sampled from the
  entire labor-eligible population instead of the `want_work` subset it was
  meant to upgrade, inflating simulated labor-force participation (81.7% vs.
  census 62.2%).
- **Census data**: Jerusalem's `sa_data_b7.csv` had corrupted household-size
  percentage columns (summing to a mean of 144% instead of ~100%, with many
  rows showing exact duplicate values across supposedly-independent size
  buckets) — the root cause of the remaining FAILs after all four code fixes
  above. Patched from a second, independently-sourced clean census export;
  original preserved at `JER/sa_data_b7_ORIGINAL_BACKUP.csv`.

If another city's validation shows FAILs in the household-size/kid-share/
adult-share cluster, check the census file's size-bucket columns sum to
~100% first — that failure mode is bad input, not bad code, and no code
change fully substitutes for a clean source file.

---

## Policies and mechanisms

Full mechanism-level detail (data structures, exact formulas, per-step
sequencing) lives in [`sheltering_logic.md`](sheltering_logic.md) — this
section is a summary.

### Sheltering — three tiers

1. **Immediate (public buildings + hotels).** Displaced households are placed
   into public/school buildings and hotels — hotels tried first, then
   public/school
   ([`assign_shelter.m`](assign_shelter.m)/[`release_shelter.m`](release_shelter.m)).
   Capacity: `agents_per_sqm * public_bldg_usable_fraction * Area * floors`
   for public/school; `hotel_room_density * agents_per_room * Area * floors`
   for hotels. `restrict_public_shelters_to_schools` (default: on) lets "all
   public buildings" vs. "schools only" be compared as separate policy runs.
   `hotel_room_density` is now calibrated for both Tiberias (39 buildings,
   real CBS hotel-count data, see
   [`identify_hotels_TVR.m`](identify_hotels_TVR.m)) and Ashkelon (3
   buildings, see [`identify_hotels_ASH.m`](identify_hotels_ASH.m)).

2. **Medium-term (temporary developments).** A fixed number of abstract
   residential spaces (`n_temp_dev_sites=3`) — **not buildings**: no
   `Build_Data` row is ever created, so they're automatically excluded from
   the housing market. Open `temp_dev_delay` weeks after the shock, combined
   capacity = `temp_dev_capacity_frac` × total currently-sheltered population
   split evenly across sites. Filled in **strict priority order** (not a
   shuffled pool): public/school-sheltered households first, then
   out-of-city overflow households, then hotel-sheltered households last —
   hotels are the most comfortable of the immediate options, so those
   households are the last moved into container-city conditions. Shuffled
   only *within* each tier. Applies identically in both a limited-capacity
   and a full-capacity (`temp_dev_capacity_frac=1`) scenario — only the
   total capacity differs, not the fill order. Close after
   `temp_dev_duration` weeks — remaining residents force-released to the
   out-of-city pool (unless `tempdev_patience_duration` triggers permanent
   departure first — see below).
   ([`site_temp_dev_locations.m`](site_temp_dev_locations.m)/[`release_temp_dev.m`](release_temp_dev.m))

3. **Out-of-city overflow.** When the immediate tier runs out of capacity,
   leftover displaced households are tracked as "sheltered outside the city,
   commuting in" with a flat income penalty (`outside_commute_penalty_pct`)
   and suppressed local-activity routines.
   ([`release_outside_shelter.m`](release_outside_shelter.m))

All three tiers share the same exit logic: a household is released once its
original home building recovers, or it secures a new asset through the
normal housing search. `HH_data` itself is deliberately never repointed away
from a household's destroyed home while sheltered (so those recovery/exit
conditions still work correctly), but a sheltered household's *routine*
(non-work activity locations) **is** recomputed to anchor on wherever it's
actually living — the assigned shelter building, or the temp-dev site's
coordinates — via `routine_home_override`/`routine_recompute_ids`.

### Two-stage search design

**Stage 1** (from the shock until temp-dev opens, `i < shock_step +
temp_dev_delay`): no displaced household searches for new housing at all —
neither immediate/hotel-sheltered nor outside-overflow households are folded
into `moving_HH`. Reconstruction (the independent per-building recovery
draw) proceeds regardless. **Stage 2** begins once temp-dev opens; from then
on every displaced household searches every step like any other mover.

### Decreasing patience — permanent departure from the simulation

Unlike the original design (where no sheltered household was ever deleted),
a household that has been unsheltered/under-sheltered for too long with no
resolution now permanently leaves the simulation, via the same
`did_not_find_house` path any ordinary migrant uses after repeatedly failing
to find housing:

- **`outside_patience_duration`** (default 4 weeks) — applies to
  out-of-city overflow households (`Sheltered_Outside`), and to households
  displaced by a land-use conversion of their home to commercial use (see
  `LU_Displaced` below). Elapsed time is measured from whichever is later:
  the household's own entry into the pool, or stage-2 onset — since stage 1
  has no search attempts at all, the patience clock can't start before
  stage 2 regardless of nominal entry time.
- **`tempdev_patience_duration`** (default `Inf` — no per-household cap,
  preserving the original site-level-only closure behavior) — same
  mechanic, for households in `Temp_Dev_Assign`. Set together with
  `temp_dev_duration=Inf` to replace the site-closure/transfer mechanic
  entirely with a clean "N steps in temp-dev or permanently displaced" rule.
- Recovering the original home or securing a new asset always takes
  priority and releases a household from these pools first — patience-based
  departure only ever catches households still genuinely unresolved once
  time runs out.
- Tracked in `n_permanently_displaced_total`/`n_permanently_displaced_track`
  — the only channel through which shock-caused population loss doesn't
  eventually recover.

### Land-use eviction retry (`LU_Displaced`)

Households whose home gets converted to commercial use by the land-use
block get the same multi-step retry grace period as the sheltering tiers
(`LU_Displaced` pool, `outside_patience_duration`), instead of being deleted
the same step their building converts. Needed because the land-use
conversion selection (`Change_LU`) is a percentile cut of the *entire*
eligible building stock, not just newly-crossing buildings — its first-ever
activation therefore flags a large one-time batch of the whole untouched
residential stock at once. Before this fix: ~6,250 households evicted in a
single step, overwhelming the same-step housing search and getting
force-deleted — visible in every macro trend as an early population
dip-and-recovery artifact. Retrying over several steps (like any other
displaced household already does) fixes this without touching the
conversion ranking/calibration itself.

### Building reconstruction

Each destroyed building has an independent weekly probability of recovering
(`RECOVERY`), rather than every building sharing one fixed recovery time —
calibrated from real data (31.35% of residential housing recovered within 1
year: `RECOVERY = 1-(1-0.3135)^(1/52)`). Applied uniformly to all building
types by default; `priority_recovery`/`recovery_factor` still lets residential
recovery be scenario-tested at a different rate.

### Multi-city configuration

A `city` switch/case block (top of the script) picks the data file, folder,
and calibration constants per city — see the block's own header comment for
exactly what's validated vs. a TODO placeholder.

### Land-use conversion calibration

`jobs_per_meter_multiplier`, `potential_jobs_per_meter_multiplier`,
`lu_change_rank_lower`, `lu_change_rank_upper` are overridable multipliers/
thresholds on the land-use commercial-conversion logic — multipliers on the
city's own base `JobsPerM_comm`, not absolute values, so the same
calibration philosophy applies to any city. Defaults (`1`/`1`/`20`/`40`)
reproduce the script's original, unmultiplied behavior exactly if a caller
doesn't override them. modelthesis's validated Tiberias calibration
(`3`/`2`/`45`/`85`) is set by
[`run_tiberias_calibrated.m`](run_tiberias_calibrated.m).

### Reproducibility: RNG seeding

MATLAB initializes `rand`/`randn`/`randperm` to the *same fixed default
seed* at the start of every fresh process — confirmed by two separate
`matlab -batch` invocations producing byte-identical `rand` output. This
silently made separate-process replicates (e.g. each `n_sims=1` run
launched as its own process) deterministic repeats rather than independent
draws — 5 shock replicates run this way all landed on the exact same
trajectory. The script now reseeds from time/process entropy
(`rng('shuffle')`) by default at startup; pass `rng_seed` to pin a specific
seed instead, for exact reproducibility when that's wanted.

---

## Bug fixes

### Run-model script

- **`find_new_house_sa_score.m`** — `U_sa` (SAs passing the household's
  preference threshold) was computed but never actually used to filter
  `possible_assets` before assignment, so all assets in the pool were
  considered regardless of SA score. Fixed by filtering to accepted SAs
  before calling `new_house`.
- **`locAA` zero-index crash** — `ismember` against `HH_data(:,2)` could
  return 0 for unmatched rows, crashing on the resulting zero-index into
  `HH_data`. Fixed with an explicit valid-match mask and a sentinel value for
  unmatched rows.
- **`Shelter_Assign` empty-array indexing crash** — `Shelter_Assign` starts
  as a bare `[]` (0×0), and the medium-term-sheltering transfer code indexed
  `Shelter_Assign(:,1)` unconditionally; this crashes whenever the immediate
  tier has never been used at all (e.g. `restrict_public_shelters_to_schools`
  on a city with no tagged schools). Fixed with the same `isempty` guard the
  rest of the codebase already used elsewhere.
- **Land-use percentile-ranking loops (performance)** — see Optimizations
  below; not a correctness bug, but worth listing alongside the other
  land-use-block changes.
- **`new_house.m` never synced a household's SA after a cross-SA move** —
  `HH_data`'s SA column (col 1) was only ever set at initial assignment; a
  household relocating to a different SA (via same-yeshuv/other-yeshuv
  matching) kept its *old* SA on record forever. This silently broke every
  SA-level metric/map for cross-SA movers, and made `who_is_moving.m`
  evaluate those households under their stale original SA's move
  probability going forward. Within-SA moves were unaffected. Fixed by
  syncing `HH_data(FFF1,1)` to the new asset's SA on every assignment.
- **Housing search not filtering by residential zoning** — candidate asset
  pools in `find_new_house_same_stat.m`/`find_new_house_yeshuv.m` included
  assets inside buildings that had already converted to commercial (their
  `Assets` rows are vacated on eviction but never deleted, so they kept
  showing up as valid vacant housing). Fixed with a shared helper,
  `filter_residential_assets.m`, applied everywhere candidate assets get
  pulled in both functions.
- **Lost-jobs mechanism unemploying the wrong people** — when a building's
  commercial usage got flagged for job loss, every current employee matched
  by *building* ID got laid off, even on multi-job buildings only supposed
  to lose one slot. Fixed by tracking the specific work_place_ids that
  actually closed that step (`closed_wp_ids_today`) and matching individuals
  against that list (col 17, the specific slot), not the building.
- **`SA_LOCAL` checking a column that can never hold the value it tests
  for** — the formula checked `Individuals_data(:,12)==99` to detect "works
  outside the city," but col 12 (working status) is only ever 0/1/2 for any
  employed person, local or outside — the local/outside distinction lives
  in col 15. This pinned `SA_LOCAL` at exactly 1.0 regardless of the real
  split (confirmed after the fix: now varies ~0.45–0.89 across SAs in a
  smoke test). Fixed by checking col 15 instead, and restructuring
  numerator (local workers) vs. denominator (all workers) accordingly.
- **"Add people to working market" applying to the wrong population** — the
  code correctly computed a probability-scaled sample size and drew a
  random sample `P` of that size from the eligible pool `F`, then discarded
  `P` and applied the status change to the entire pool `F` instead. This
  pushed everyone eligible into job search whenever the economy was even
  slightly tight. Fixed by changing `Individuals_data(F,12)=1` to
  `Individuals_data(P,12)=1`.
- **`SA_POP_RATIO`/`SA_ASSET_RATIO`/`SA_SERVICE_RATIO` divide-by-uninitialized-column** —
  these ratios compare the current month's SA-level population/asset/service
  count against "4 steps ago," but the code was reading column `i` (the
  trigger step itself, e.g. 4, 8, 12 — never actually written) instead of
  column `i-3` (the last populated column, e.g. 1, 5, 9). The `i`-column read
  auto-grows as 0, so every single monthly update divided by zero →
  `Inf` → `nanmean` (which doesn't filter `Inf`, only `NaN`) → this
  poisoned `Assets(:,12)`/`(:,13)` (price/monthly-cost) **city-wide**, every
  4 steps, breaking affordability checks for essentially all housing search
  that step. Root cause of a severe population-collapse bug for Tiberias
  (observed: ~90% population loss over 30 steps) and, less visibly, meant
  the intended price-growth-tracks-population/asset/service-growth feedback
  never actually engaged in *any* prior run of this script, for any city.
  Fixed by comparing against column `i-3` instead of `i`, with a `>0` guard
  (falls back to a neutral ratio of 1 if even that's somehow unpopulated).
- **Ambiguous household-ID guard (`LU_Displaced` retry pool)** — household
  IDs are minted via `max(HH_data(:,2))+1` at creation (e.g. by
  `migration_19.m`); if the household holding the running-max ID is later
  deleted, a subsequent migrant can be issued that same numeric ID again,
  producing two `HH_data` rows sharing one ID. Rare in general, but the
  odds of hitting it are much higher for a large, long-lived retry pool like
  `LU_Displaced`, where `find_new_house_same_stat` assumes exactly one match
  per ID and errors on a size mismatch otherwise. Fixed by detecting
  duplicate IDs (`accumarray` count > 1) and excluding them from the retry
  batch defensively.
- **Tiberias `intraSAProb`/`intraYeshuvProb` misread as daily rates** —
  `read_sas_data.m` converts these columns from daily to weekly probability
  (`1-(1-p)^7`), confirmed correct for Ashkelon, but Tiberias's raw values
  are ~1000x larger (median `intraSAProb` 0.0256 vs. Ashkelon's 0.0000336) —
  the same "dimensionless ratio misused as a rate" pattern already found for
  `inOutRatio` in this same file. Reinterpreting Tiberias's raw values as
  **annual** rates instead (`1-(1-p)^(7/365)`) brings them within ~2–5x of
  Ashkelon's scale (not ~1000x), and empirically fixed both the model's
  behavior (previously ~10–48% of the population attempting a move every
  single week) and performance (Tiberias was running 11.7x slower than
  Ashkelon per step *despite having fewer households* — now faster than
  Ashkelon, as expected for its smaller population). Applied Tiberias-only,
  right after the `read_sas_data` call in
  `run_model_earthquake_shelteroverflow.m`; Ashkelon's values are untouched.
- **Tiberias `inOutRatio` growth-rate overshoot** — kept `migration_19.m`'s
  existing mechanism (treats `inOutRatio` as an annual vacancy-fill rate
  against each SA's empty-housing count — not switched to a real-growth-rate
  approach), but Tiberias's raw values produced far too much population
  growth: a 200-step (~3.85 year) no-shock baseline grew population
  17,966 → 31,804 (+77%) vs. the +4.3% expected from real per-SA Tiberias
  census growth data (`modelthesis/TVR/real_growth_rates.csv`, +1.11%/year
  city-wide average) — a ~17.7x net-growth overshoot. Applied an empirical
  scalar correction (`intra_SA(:,5) / 17.7`), Tiberias-only, in the same
  location as the `intraSAProb` fix above. Re-verification after applying
  landed at +8.1% (still ~1.9x the +4.3% target, likely single-run
  stochastic noise from a one-run calibration estimate — left as-is rather
  than further tuned).

### Data allocation

- **`distribute_workers.m` out-of-bounds crash** — `worker_Metro_zone`
  (labor demand per metro zone) was computed once from a SA's *original*
  available-worker pool, but that pool shrinks as workers get assigned
  across the same loop; by the second metro zone the demand figure could
  exceed what was actually left, indexing past the end of the remaining
  worker array. Fixed by clamping demand to the currently-remaining worker
  count before each zone's assignment, with defensive handling for missing
  commuting-probability data.

---

## Updates from recent design review

### Temporal resolution: daily → weekly steps

Every mechanically-fixable daily rate/duration/cadence constant was
converted to its weekly equivalent — `RECOVERY`, `subsidy_duration`, the
`VISITS` rolling window, `lu_warmup`, the SA/price update cadence, the
job-search patience curve, `migration_19.m`'s `inOutRatio`,
`read_sas_data.m`'s `intraSAProb`/`intraYeshuvProb`, and the medium-term
sheltering timing constants. `lu_update_every` (land-use update cadence) was
deliberately left unconverted — an explicit policy choice, not a unit
conversion. The wage-adjustment mechanism (`income_ratio`, driven by
`alfa/beta/lamda/delta`) was tested empirically rather than analytically
fixed (see Untested/Outstanding below) and accepted as-is. Full derivation
table and decision log: [`day_to_week_step_rescaling_audit.md`](day_to_week_step_rescaling_audit.md).

### Validation added

- Empirical daily-vs-weekly comparison methodology (4 replicates each, fixed
  real-world time span, no-shock baseline) — used for both the wage-
  adjustment test and the job-search investigation below. Reusable pattern
  for testing any future step-size-sensitive mechanism.
- Numerical regression testing for the land-use vectorization changes (200
  randomized trials, old-loop output vs. new-vectorized output, including
  edge cases) before those changes were considered safe to commit.
- Reconstruction-rate mechanism validated against its own theoretical
  expectation (observed ~35.3% recovered after 60 weeks vs. ~35.2%
  predicted).

### Design changes still open (not yet implemented)

Raised in review but not built yet — flagged here rather than silently
deferred:

- **Housing search informed by the household's previous asset.** Currently a
  sheltered household's housing search is identical to any other mover's,
  with no reference to the asset it lost (price tier, size, SA).
- **Out-of-city commuting agents' routines.** Currently a blunt placeholder:
  all non-work routine columns are hard-suppressed (NaN'd) plus a separate
  flat income penalty. The intended design is more specific — routines
  starting at the workplace, with the commute penalty factored into the
  *computed number of activities* rather than just zeroing everything out.

---

## Untested parameters / validation still needed

**Uncalibrated placeholders** (present in the code, not yet set through
sensitivity testing): `agents_per_room`, `public_bldg_usable_fraction`,
`outside_commute_penalty_pct`, `temp_dev_capacity_frac`, `temp_dev_duration`,
`temp_dev_delay`. `outside_patience_duration` (default 4 weeks) was set from
a single empirical comparison against Ashkelon's shock+hotels scenario (56
permanent departures out of a ~471 peak overflow at 4 steps, vs. just 1 at
the previous default of 13) — re-validate if `steps`/`shock_step` change
substantially, and note it hasn't been checked against Tiberias's shock
scenario at all. `tempdev_patience_duration` defaults to `Inf` (off).

**Temporal-resolution gaps identified but not resolved:**
- **Job search** — confirmed structural issue. Each job-seeker gets exactly
  one match attempt per open position per step, regardless of step length;
  empirically, a disruption of comparable size resolves in ~3 days under
  daily steps but takes ~7 weeks under weekly steps once vacancies are
  scarce (e.g. right after an earthquake). Not yet fixed.
- **Land-use churn thresholds** — the fixed rank-diff thresholds
  (`new_jobs`/`lost_jobs`/`Change_LU` bands) may trigger land-use changes at
  a different real-world rate now that snapshots are a week apart instead of
  a day apart. Flagged as plausible, not empirically tested.
- **Housing search volume** — reviewed and found not to need changes (a
  household evaluates the full currently-vacant asset pool per attempt, no
  per-step throttle analogous to job search).

**Superseded — see Bug fixes above for what was actually done:**
- The `who_is_moving.m` daily-vs-annual question and the `migration_19.m`
  growth-rate overshoot were both revisited after this note was originally
  written. The daily-rate premise held for Ashkelon but **not** for
  Tiberias (its raw `intraSAProb`/`intraYeshuvProb` are ~1000x larger than
  Ashkelon's) — Tiberias now gets an annual-rate reinterpretation,
  Ashkelon is untouched. `migration_19.m`'s mechanism itself was
  deliberately kept as-is (not switched to a real-growth-rate approach —
  real per-SA growth data only exists for Tiberias, not Ashkelon), but
  Tiberias's `inOutRatio` now gets an empirical scalar correction to bring
  simulated growth back in line with real census data. See the two Tiberias
  entries in Bug fixes above for the full detail and evidence.

**Other unfinished items:**
- Arad has no compiled dataset yet (a city option exists, but there's
  nothing to select).
- Hotels are identified/tagged for Ashkelon and Tiberias only; other cities
  have no hotel shelter capacity.
- Land-use-submodel and job-creation dynamics don't yet account for hotel
  buildings (usage=7) as a participating building type.
- Tiberias's `inOutRatio` calibration factor (`/17.7`) was derived from a
  single no-shock 200-step run and hasn't been re-validated against a shock
  scenario or a different run length.

---

## Performance

`run_uid` (OS process ID) is now baked into every output filename — lets
multiple independent `matlab -batch` invocations (different parameter
combinations, different replicates) run concurrently without overwriting
each other's saved output. The model's per-step loop is inherently
sequential (each step depends on the previous one's state) and isn't a
target for internal parallelization; parallelism here means running multiple
independent simulations at once, which this filename fix makes safe.

Three percentile-ranking loops in the land-use block were replaced with
vectorized equivalents (visit-count ranking, salary ranking, and the
commercial-conversion candidate ranking) — verified with 200 randomized
regression trials comparing old-loop output to new-vectorized output before
being applied (this caught a real off-by-one error and a single-candidate
edge case in the first draft of the vectorization).

The monthly SA-metrics update block (25 metrics — price, population, jobs,
wages, service ratios, etc., every 4 steps) was similarly vectorized (ported
from `modelthesis/run_model_earthquake.m`, commit `9b078e7`): a ~20-SA loop
that rescanned the *entire* `Assets`/`Build_Data`/`Work_places`/
`Individuals_data`/`HH_data` arrays from scratch for every one of ~22
metrics is now precomputed group indices + `accumarray` — verified
numerically identical to the original (25/25 metrics matched exactly on
real Tiberias data, one metric differing by `9e-13`, pure floating-point
summation-order noise).

Tiberias-specific: the `intraSAProb`/`intraYeshuvProb`/`inOutRatio` fixes
described in Bug fixes above were also, incidentally, a major performance
fix — the misread rates caused ~5,755 expensive housing-search calls per
step (a huge share of the population attempting a move every single week),
making Tiberias run **11.7x slower than Ashkelon despite having fewer
households**. After the fix, a 200-step 2-replicate Tiberias baseline
completes in ~8–17 minutes (was previously taking multiple days and, in one
case, never completing at all).
