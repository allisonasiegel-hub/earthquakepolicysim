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
`[file,'earthquake_damage.csv']` for whichever city is selected. See Quick
Start below for the ready-made driver scripts that set this up for you.

`run_model_earthquake.m` is an earlier, simpler variant without the
out-of-city overflow tier (see Policies section) — kept for reference, not
actively maintained in parallel with the main script.

---

## Quick Start

To run a validated scenario for a city, use its driver script directly — in
MATLAB, `run('<driver_name>.m')`, or open it and run from the editor.

| City | Baseline (no shock) | Shock scenario |
|---|---|---|
| Ashkelon | [`run_ashkelon_baseline_step25_150.m`](run_ashkelon_baseline_step25_150.m) | [`run_ashkelon_shock_step25_150.m`](run_ashkelon_shock_step25_150.m) |
| Tiberias | [`run_tiberias_calibrated.m`](run_tiberias_calibrated.m) | [`run_tiberias_shock_step25_150.m`](run_tiberias_shock_step25_150.m) |
| Jerusalem | [`run_jerusalem_calibrated.m`](run_jerusalem_calibrated.m) | — (not yet validated for a shock scenario) |

Output saves to `earthquakeF/<prefix> EQ S <timestamp> <replicate#> <pid>.mat`.
Re-running a driver adds more replicates on top of whatever's already there,
rather than overwriting previous output.

For the reasoning behind the specific settings these drivers use
(`shock_step=25`, `steps=150`, etc.), see "Validated shock scenario
configuration" under Policies and mechanisms below.

---

## Standard output

To generate a standard report from one or more runs, use
[`plot_macro_comparison.py`](plot_macro_comparison.py):

```
python plot_macro_comparison.py --city Ashkelon
python plot_macro_comparison.py --city Ashkelon --city Tiberias   # side-by-side comparison
```

This produces, in `plots_macro_comparison/` by default (`--out` to change it):

- `macro_trends.png` — overview grid, all 30 `SA_*` macro variables
  (population, prices, jobs, wages, etc.) at a glance
- `macro_trends.pdf` — one full-size page per variable, preceded by a
  shelter & reconstruction outcomes table and, for any scenario with a
  firing shock, total-households-sheltered and cumulative-permanent-
  displacement pages
- `macro_pngs/<VAR>.png` — each variable as its own PNG
- `shelter_tiers.png` / `total_sheltered.png` / `permanent_displacement.png`
  — the same shock-scenario outcome charts as standalone PNGs

**Caveat:** baseline and shock runs of the same city share the same
`earthquakeF/` filename prefix (see Quick Start above), so `--city Ashkelon`
sweeps in *every* Ashkelon run ever saved there, mixing baseline and shock
replicates together. To isolate one specific run (or compare exactly two),
use `--pattern` with that run's own timestamp instead:

```
python plot_macro_comparison.py --pattern "Ash2hotels EQ S 20260915_1401*" --label "My shock run"
```

---

## Data

### Data required to run the model directly

Each city needs a compiled `.mat` dataset containing `Assets`, `Build_Data`,
`HH_data`, `Individuals_data`, `Work_places` (plus their `_P`/`_p`
header-name companions), a `sas_national.xlsx` and `commuting.xlsx` in that
city's data folder, and a per-SA `earthquake_damage.csv` (columns `SAID`,
`dmg_prc`) to actually trigger a shock.

Use the hotel-tagged dataset for each city — `data_for_model_Ash2hotels.mat`
(Ashkelon) / `data_for_model_TVR_hotels.mat` (Tiberias). Both cities have
hotel buildings tagged (usage=7) as a shelter type:
[`identify_hotels_ASH.m`](identify_hotels_ASH.m) (3 buildings, Ashkelon) and
`identify_hotels_TVR.m` (39 buildings, Tiberias).

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

### Validating a city's allocation output

`data_allocation/validate_allocation.py` / `plot_allocation.py` check a
compiled city's synthetic population against the census data it was built
from. City-agnostic: `python validate_allocation.py --city JER` derives all
paths from the city name. Full usage and how to interpret a FAIL:
[`data_allocation/VALIDATION_AND_FIXES.md`](data_allocation/VALIDATION_AND_FIXES.md).

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
  displaced by a land-use conversion of their home to commercial use
  (`LU_Displaced`). Elapsed time is measured from whichever is later:
  the household's own entry into the pool, or stage-2 onset — since stage 1
  has no search attempts at all, the patience clock can't start before
  stage 2 regardless of nominal entry time.
- **`tempdev_patience_duration`** (default 8 weeks) — same mechanic, for
  households in `Temp_Dev_Assign`. Set together with `temp_dev_duration=Inf`
  to replace the site-closure/transfer mechanic entirely with a clean "N
  steps in temp-dev or permanently displaced" rule.
- Recovering the original home or securing a new asset always takes
  priority and releases a household from these pools first — patience-based
  departure only ever catches households still genuinely unresolved once
  time runs out.
- Tracked in `n_permanently_displaced_total`/`n_permanently_displaced_track`
  — the only channel through which shock-caused population loss doesn't
  eventually recover.

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

### Validated shock scenario configuration

The standard shock-scenario setup (`shock_step`, `steps`, and whether
`temp_dev_duration`'s site-closure mechanic runs alongside patience-based
departure) was originally validated empirically for Ashkelon, then
independently re-checked and ported to Tiberias (2026-09-15):

- **`shock_step=25`, `steps=150`** — `shock_step` needs to clear the
  land-use module's initial-activation transient (a one-time large
  conversion batch when land-use first turns on) before the shock hits,
  or the two effects confound each other. Checked per-city via a
  no-shock baseline's `SA_SERVICE` (commercial building count)
  trajectory: Ashkelon settles by ~week 20-21; **Tiberias settles by
  week 8** (`SA_SERVICE` flat from step 8 through step 200 in a 200-step
  no-shock baseline) — `shock_step=25` clears Tiberias's transient with
  an even larger margin than it does for Ashkelon's.
- **`temp_dev_duration=Inf`** — disables the site-level force-close/
  transfer-to-overflow mechanic, so temp-dev departures happen only via
  `tempdev_patience_duration` (per-household patience) instead of two
  competing exit mechanisms. See "Decreasing patience" above.
- Ready-made drivers: see Quick Start above.
- `n_sims=1` (run as its own process) is used for the shock driver,
  mirroring Ashkelon's same caution — that scenario type has an
  unexplained-crash history at `n_sims>=2` in one process for Ashkelon;
  untested whether Tiberias shares it at this exact parameter
  combination, so treated the same way defensively.

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
  growth against real per-SA Tiberias census growth data
  (`modelthesis/TVR/real_growth_rates.csv`, +1.11%/year city-wide average).
  Applied via an overridable `tiberias_inoutratio_scale` (default `1.79`,
  empirically calibrated against `data_for_model_TVR_hotels.mat` — the
  current, validated Tiberias dataset), dividing `intra_SA(:,5)` by it,
  Tiberias-only, in the same location as the `intraSAProb` fix above.
  Re-derive this value (see the calibration comment right above where
  `tiberias_inoutratio_scale` is set) if the dataset is regenerated again.

### Data allocation

- **`distribute_workers.m` out-of-bounds crash** — `worker_Metro_zone`
  (labor demand per metro zone) was computed once from a SA's *original*
  available-worker pool, but that pool shrinks as workers get assigned
  across the same loop; by the second metro zone the demand figure could
  exceed what was actually left, indexing past the end of the remaining
  worker array. Fixed by clamping demand to the currently-remaining worker
  count before each zone's assignment, with defensive handling for missing
  commuting-probability data.
- **`create_HH_12_2018.m`** — elderly-household count was being recomputed
  from a raw population headcount partway through the function, overriding
  the correct, earlier household-based estimate and badly over-assigning
  elderly status (38% vs. census 27%).
- **`labor_datasample.m`** — "currently working" status was sampled from the
  entire labor-eligible population instead of the `want_work` subset it was
  meant to upgrade, inflating simulated labor-force participation (81.7% vs.
  census 62.2%).

---

## Untested parameters / validation still needed

**Uncalibrated placeholders** (present in the code, not yet set through
sensitivity testing): `agents_per_room`, `public_bldg_usable_fraction`,
`outside_commute_penalty_pct`, `temp_dev_capacity_frac`, `temp_dev_duration`,
`temp_dev_delay`. `outside_patience_duration` (default 4 weeks) and
`tempdev_patience_duration` (default 8 weeks) were both calibrated against
Ashkelon's shock scenario and ported to Tiberias without independent
Tiberias-specific sensitivity testing of the durations themselves (only the
surrounding `shock_step`/`steps`/`temp_dev_duration` configuration was
independently re-verified for Tiberias — see "Validated shock scenario
configuration" above); permanent-displacement counts are sensitive to these,
so revisit if that matters for a given run.

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

**Other unfinished items:**
- Arad has no compiled dataset yet (a city option exists, but there's
  nothing to select).
- Hotels are identified/tagged for Ashkelon and Tiberias only; other cities
  have no hotel shelter capacity.
- Land-use-submodel and job-creation dynamics don't yet account for hotel
  buildings (usage=7) as a participating building type.
- Tiberias's `inOutRatio` calibration factor (`tiberias_inoutratio_scale`,
  default `1.79`) was derived from a single no-shock 200-step run and
  hasn't been re-validated against a shock scenario or a different run
  length.
