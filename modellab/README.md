# Earthquake Policy Simulation — Ashkelon/Tiberias ABM

## Purpose

This is a MATLAB agent-based model (ABM) simulating a city's housing, labor, and
business markets before and after an earthquake, used to test the effect of
different post-disaster policy choices — where displaced households shelter,
how quickly buildings get rebuilt, how the local economy absorbs the shock —
on recovery outcomes over time.

**Main run script:** [`run_model_earthquake_shelteroverflow.m`](run_model_earthquake_shelteroverflow.m).
Set `city` (`'Ashkelon'` or `'Tiberias'` — see Data section) and `shock_step`
before calling `run()`; a per-SA damage table must exist at
`[file,'earthquake_damage.csv']` for whichever city is selected. Only
Ashkelon's calibration constants (`commute_outside`, `alfa/beta/lamda/delta`)
are currently validated — other cities error out immediately if selected
without filling those in, rather than running on placeholder numbers.

`run_model_earthquake.m` is an earlier, simpler variant without the
out-of-city overflow tier (see Policies section) — kept for reference, not
actively maintained in parallel with the main script.

---

## Data

### Data required to run the model directly

Each city needs a compiled `.mat` dataset (e.g. `data_for_model_Ash2.mat`,
`data_for_model_TVR_hotels.mat`) containing `Assets`, `Build_Data`, `HH_data`,
`Individuals_data`, `Work_places` (plus their `_P`/`_p` header-name
companions), and a `sas_national.xlsx` (15-column raw layout — see the city
configuration block's comments for a documented incompatibility with
Ashkelon's `ASH22\sas_national.xlsx`, a different 5-column pre-summarized
format) and `commuting.xlsx` in that city's data folder. A per-SA
`earthquake_damage.csv` (columns `SAID`, `dmg_prc`) is required to actually
trigger a shock.

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
   into public/school buildings and hotels
   ([`assign_shelter.m`](assign_shelter.m)/[`release_shelter.m`](release_shelter.m)).
   Capacity: `agents_per_sqm * public_bldg_usable_fraction * Area * floors`
   for public/school; `hotel_room_density * agents_per_room * Area * floors`
   for hotels. `restrict_public_shelters_to_schools` lets "all public
   buildings" vs. "schools only" be compared as separate policy runs.
   `hotel_room_density` is currently only calibrated for Tiberias (from real
   CBS hotel-count data, see [`identify_hotels_TVR.m`](identify_hotels_TVR.m));
   Ashkelon has no hotels tagged yet.

2. **Medium-term (temporary developments).** A fixed number of abstract
   residential spaces (`n_temp_dev_sites=3`) — **not buildings**: no
   `Build_Data` row is ever created, so they're automatically excluded from
   the housing market. Open `temp_dev_delay` weeks after the shock, combined
   capacity = `temp_dev_capacity_frac` × total currently-sheltered population
   split evenly across sites, filled from a randomly-shuffled combination of
   the immediate tier and the out-of-city overflow pool. Close after
   `temp_dev_duration` weeks — remaining residents force-released to the
   out-of-city pool.
   ([`site_temp_dev_locations.m`](site_temp_dev_locations.m)/[`release_temp_dev.m`](release_temp_dev.m))

3. **Out-of-city overflow.** When the immediate tier runs out of capacity,
   leftover displaced households aren't deleted — they're tracked as
   "sheltered outside the city, commuting in" with a flat income penalty
   (`outside_commute_penalty_pct`) and suppressed local-activity routines.
   ([`release_outside_shelter.m`](release_outside_shelter.m))

All three tiers share the same exit logic: a household is released once its
original home building recovers, or it secures a new asset through the
normal housing search. No sheltered household is ever deleted from the
simulation while waiting.

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
- **Routine recomputation using the shelter as "home."** A household's
  `HH_data` is deliberately never repointed away from its destroyed home
  while sheltered (so the recovery/exit conditions work correctly), but
  nothing currently recomputes a sheltered household's *routine* (non-work
  activity locations) to anchor on the shelter it's actually living in — its
  local-activity routine is still computed relative to the old, destroyed
  home's location.
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
`temp_dev_delay`.

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

**Considered and intentionally not applied:**
- **`who_is_moving.m` daily-vs-annual question — resolved, no change made.**
  A candidate fix treats `intraSAProb`/`intraYeshuvProb` as *annual* rates,
  not daily probabilities, based on a different project's data source. Since
  there's no `/365` (or any scaling) anywhere in this codebase's path for
  these columns, that implies whatever conversion was needed was already
  done upstream in this project's own `sas_national.xlsx` - the daily-rate
  premise behind the existing day-to-week conversion in `read_sas_data.m`
  (`1-(1-p)^7`) stands. Not ported.
- **`migration_19.m` in-migration growth-rate fix — deliberately excluded.**
  A candidate fix (addressing a ~21x in-migration overshoot in its source
  project) applies each SA's real annual population growth rate to its
  current household count instead of treating `inOutRatio` as a vacancy-fill
  fraction. Real per-SA growth-rate data only exists for Tiberias, not
  Ashkelon, and the fix depends on a `filter_residential_assets.m`-style
  helper. Decision: leave `migration_19.m` as-is for now.

**Other unfinished items:**
- Arad has no compiled dataset yet (a city option exists, but there's
  nothing to select).
- `commute_outside`/`alfa`/`beta`/`lamda`/`delta` are uncalibrated (`NaN`)
  for every city except Ashkelon.
- Hotels are only identified/tagged for Tiberias; Ashkelon and other cities
  have no hotel shelter capacity.
- Land-use-submodel and job-creation dynamics don't yet account for hotel
  buildings (usage=7) as a participating building type.

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
