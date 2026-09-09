# Handover — Tiberias ABM thesis work (modelthesis/)

Written for a fresh Claude Code chat picking up this repo with no memory of
the prior conversation. Covers everything from git commit `f85975c` ("Fix
retry/migration/relocation bugs in earthquake model; add old-old
service-weight differentiation") through the current, **partially
uncommitted** working tree. Read this before touching any of the files
below.

## READ THIS FIRST — the floorspace variant + earthquake-shock framework

**Everything below this box, through §9, predates commit `f32827f` and knows
nothing about the floorspace-weighted model or the earthquake-shock work.**
Almost none of that later work is committed to git (§10 explains why git
history is not a reliable map of it), so if you're touching
`run_model_earthquake_floorspace.m`, `run_earthquake_setting_floorspace.m`,
`building_service_density.m`, `building_service_ratio_floorspace.m`,
`filter_by_building_service.m`, any `analysis_scripts/*_v2.py` script, or
any `earthquakeF/*floorspace*.mat` output — **go read §10 first**, then come
back here for the pre-existing (still-accurate for the count-based,
non-floorspace, non-shock model) history. §3's "band 60-80 locked in" is
specifically superseded for the floorspace variant — see §10.3.

**Also check §11** if you're inside (or being asked to work in) the git
worktree at `.claude/worktrees/elderly-search-methodology` — a
SEPARATE, not-yet-merged branch with its own additional floorspace/
elderly-search work (distribution maps, a mode-1 floorspace retest, a
partial 550-day multi-mode batch) plus a Tiberias-calibration transfer
into the sibling `modellab/` project. None of §11 exists in the normal
`modelthesis/` working tree unless you're specifically told you're in
that worktree.

**Before any run or any age-split analysis, read §12.** The young-old /
old-old split was being read off the wrong `HH_data` column and was fixed
(uncommitted, with a new untracked `hh_age_group.m`). It changes results for
every mode, including the finalized mode 2, and invalidates age-split
comparisons against older `earthquakeF/*.mat` outputs.

## QUICK REFERENCE (added in a later session — read this first if you just
## want current status, not the full history below)

- **Finalized methodology: plain mode 2, no eld_movef.**
  `elderly_search_mode=2` (SA-level hard filter + weighted SA pick for
  out-of-SA moves, old-old weighted more strongly than young-old),
  `svc_filter=1` (mode 2's within-SA hard building-level floor). These are
  now the DEFAULTS in both `run_model_earthquake.m` and
  `run_earthquake_setting.m` — search for "FINALIZED METHODOLOGY" comments
  in either file for the full rationale. Canonical run script:
  `run_final_methodology.m`. Modes 1, 3, 4, 5, 6 and an eld_movef
  (movement-probability reduction) variant were all tested and rejected in
  favor of mode 2 — see `find_new_house_sa_score.m`'s header comment for
  every mode's mechanics.
- **Standard results output**: `python analysis_scripts/standard_report.py
  <config>` (e.g. `mode2`, `mode6`, `baseline`) produces a results table
  (SA/building service level, SA/city success rate, normalized assets —
  avg±std per population group, with significance asterisks) plus
  Metric_Track trend plots and all 24 SA_* macro-economic trend plots
  (overview grid PNG + one-page-per-variable PDF + individual PNGs), all
  in one command. Run it from `modelthesis/`. Self-contained, no other
  context needed.
- **Shock-vs-baseline delta output**: `python analysis_scripts/
  shock_delta_report.py <scenario_pattern> [<scenario_pattern2> ...]`
  compares one or more shock scenarios (e.g. `shock_mode2`, and later an
  intervention variant) against a single fixed baseline (default:
  `760day_mode2`, i.e. the finalized methodology with no shock — override
  with `--baseline`). NOT a mode-vs-mode comparison — the methodology
  (mode 2) is fixed; what varies is the shock scenario. Reports the same 6
  metrics x 3 population groups as the table above, as deltas, with
  significance once both sides have >=2 replicates.
- Confirmed replicate counts as of this note: baseline n=7, mode1 n=4,
  mode2 n=10, mode3 n=10, mode4 n=4, mode5 n=10, mode6 n=4 (plus several
  eld_movef variants at n=4-8, ultimately not used in the final choice).

## 0. Current repo state — READ FIRST

- Committed up through `9b078e7` ("Fix labor-market/metric bugs and
  vectorize hot loops in run_model_earthquake.m").
- **Uncommitted changes sit in the working tree right now** on top of that
  commit, in: `run_model_earthquake.m`, `run_earthquake_setting.m`,
  `migration_19.m`, `find_new_house_same_stat.m`, `find_new_house_yeshuv.m`,
  and `analysis_scripts/plot_sim_results.py`. These are real, validated
  fixes (see §4 items 9-11 and §6) — not work-in-progress. Whoever picks
  this up should decide whether to commit them before continuing (the user
  did not ask for that commit yet as of this handover).
- Main script: `run_model_earthquake.m`. Wrapper for single-scenario test
  runs: `run_earthquake_setting.m` (function; handles the model's
  `clearvars` cleanup and scenario-tagged output naming).
- Reference/pristine version for comparison: `run_model_eq.m` (also in this
  folder) — confirmed to match `romansunedited/run_model_eq.m` outside this
  folder in the sections checked. Several bugs below were confirmed
  present in this reference too, meaning they're inherited from the
  original model, not introduced by this thesis's changes.
- **CONCURRENCY**: used to be unsafe to run two `matlab -batch` sweep jobs
  against this directory at once (fixed non-unique output paths — silent
  cross-contamination, confirmed twice this project). This is now fixed
  (§4 item 11) — concurrent runs are safe as of the current working tree,
  but only with that fix in place. If you revert `run_earthquake_setting.m`
  without reverting the concurrency fix, the danger returns.
- Statistics and Machine Learning Toolbox and Parallel Computing Toolbox
  are both installed and licensed on this machine (confirmed this session).

## 1. wservice / wservice_old (elderly service-preference weight) — history & results

- `wservice`: weight on service-accessibility in the elderly preference
  score for **out-of-SA moves only**. Applies to young-old (65-69) and is
  the baseline. `wservice_old`: same mechanism, specifically for old-old
  (70+); defaults to `wservice` if not set separately.
  `Y = (income + age + w*service) / (2 + w)` for elderly; non-elderly
  ignore this entirely.
- Original test grid (early in the project): `[0, 0.25, 0.5, 1, 2]`.
- A 2-way ANOVA (statsmodels) confirmed `wservice` and `wservice_old` have
  **independent, additive, non-interacting** effects on old-old service
  exposure — raising one doesn't change the marginal effect of the other.
- Commit `b12f225` tested higher young-old wservice values against
  population growth — see that commit's diff for the specific runs; not
  reproduced here since it predates this handover's detailed tracking.
- **This session's specific test**: `wservice=1.0, wservice_old=1.5`,
  compared against the `wservice=0/wservice_old=0` baseline, **first with
  `svc_filter=1`**. Result: elderly SA service ratio actually *decreased*
  slightly (0.168 → 0.153) and elderly within-SA success rate dropped
  substantially (0.868 → 0.692) — the opposite of what you'd naively
  expect from raising the preference weight. See §2 for why (the filter and
  the preference weight fight each other).
- Then re-tested with **`svc_filter=0`** (same wservice values) — two full
  760-day runs exist (`760day_svcfilteroff_ws1_wsold15.mat` and a v2 rerun
  `svcfilteroff_ws1_wsold15_v2_full3way.mat` with the complete 3-way
  Metric_Track extension, see §6). **Detailed numeric comparison of this
  svc_filter-off run against baseline has not yet been written up** — the
  plots were generated and sent to the user, but the follow-up analysis
  (does removing the filter restore the expected direction of the
  service-ratio effect?) is still open. This is the natural next step.

## 2. svc_filter — history & results

- Binary switch (`0`/`1`). When `1`: for elderly households only, filters
  the within-SA candidate-asset pool to buildings with service ratio ≥ the
  household's *current* building's service ratio. Out-of-SA pools are
  never filtered by this (SA-level service preference there is handled by
  `wservice`/`wservice_old` instead). Default `0`. Test grid: `[0, 1]`.
- **Key finding this session**: `svc_filter=1` combined with
  `wservice=1.0/wservice_old=1.5` produced a *lower* average elderly
  service ratio and a much lower within-SA success rate than baseline —
  mechanically explained: the filter makes within-SA moves strictly harder
  (fewer buildings qualify), so fewer elderly households complete a move
  at all, which means fewer of them end up moving *into* higher-service
  buildings — even though their stated *preference* is pushing them toward
  wanting more service access. The filter (which gates the search) and the
  preference weight (which only shapes ranking *among* eligible options)
  work against each other rather than reinforcing.
- City-wide macro variables (population, price, service/residential/
  workplace counts) barely move either way — expected, since elderly
  households are ~23% of the population (see §6/HH_data encoding) and this
  is an elderly-specific mechanism.

## 3. Baseline threshold/parameter tuning — what was tested, results, and why the final values were chosen

This was the largest single thread of the whole project. Two real
reference targets anchored it: (a) real Tiberias census growth data
(`TVR/growthrates1.xlsx`, ~1.1%/year average — see §4 item 9-10), and (b) two
screenshots from a different paper (same underlying model architecture,
different city, COVID-shock study) giving concrete baseline (no-shock)
shape targets over 800 days: Residential Buildings ~-1.8%, Businesses
~+1.3%, Workplaces ~-1.4%, Households ~+9.5% (smooth decelerating growth),
Salary Expenses ~-2.7%, Average Wage ~+31% (steady linear growth), Price
per m² ~+4% (smooth, decelerating).

### Land-use conversion band (`lu_change_rank_lower`/`lu_change_rank_upper`)
Percentile-rank-based: a building converts to commercial if its
rank-difference (potential-salary rank minus visit rank) falls within this
band. Original: `20`/`40`. Tested `0-20`, `20-40` (original), `40-60`
(first-round tuned), `60-80` (final).
- **`0-20` band = genuine model breakdown**, confirmed via a 4-band × 3-jobs-setting
  760-step grid sweep: residential -75% to -84%, population -74% to -79%,
  workplace outcome shows a mathematically confirmed **constant compounding
  exponential growth rate** (25-45%/day-equivalent, reaching 50+ digit
  magnitudes by day 760) — a genuine runaway, not equilibrium.
- **`60-80` locked in** — best match to the reference-paper stability
  targets for residential/service.
- **SUPERSEDED for the floorspace variant (see §10.3):** widened again to
  `45-85`, a validated combo confirmed via a 10-replicate CI check. Chosen
  deliberately: it lets `SA_JOBS` reach genuine saturation (mean wage
  actually plateaus) at the accepted cost of a flatter population curve and
  workplace overbuild vs. the 60-80 band. Do not treat `60-80` as current
  for any `*_floorspace*` script.

### Job-density multipliers (`lu_jobs_per_meter`, `lu_potential_jobs_per_meter`)
Both default to the dynamically-loaded, city-correct Tiberias
`JobsPerM_comm` rate (1x). Tested at various multiples: jobs at 1.5x, 2.5x,
3x, 3.5x, 4x, 4.5x, 5x; potential at 1.5x, 2x. This is a genuine 2D
trade-off surface, not a single-direction dial:
- Higher `lu_potential_jobs_per_meter` **suppresses conversions**
  (stabilizes residential/service counts).
- Higher `lu_jobs_per_meter` **seeds more workplaces per conversion**
  (stabilizes workplace count, closes the workplace-count gap vs. the
  reference target).
- **Locked in: jobs=4.5x (`0.040197164`), potential=2.0x (`0.017865406`)**
  — found via systematic exploration of the 2D grid, balancing residential/
  service stability against workplace-count stability.

### Job-loss/creation rank thresholds
`new_jobs_rank_thresh` (unchanged at `20` throughout). `lost_jobs_rank_thresh`:
original `-20` → first-round `-60` → **final `-100`**. Pushing this out
(more negative = jobs need a much worse rank-diff before being cut) was
**the key unlock** for closing the workplace-count gap vs. the reference
target while preserving the residential/service stability already achieved
via the 60-80 conversion band — discovered after the jobs/potential
multiplier tuning alone wasn't enough.

### Wage-adjustment parameters (`wage_alfa`, `wage_beta`, `wage_lamda`, `wage_delta`)
Extensively OAT-tested twice: once against the (then-)tuned thresholds,
once against the **true original** thresholds (to rule out an
effect-masking artifact) — 22-23 independent runs each time, one value per
run. **Conclusively closed**: `alfa`, `beta`, `delta` have **no measurable
effect** on any tracked outcome across their full candidate ranges in
either regime. This holds for the *whole-trajectory* average.

**However**, a separate, narrower investigation this session (see §5 for
why it started) found `wage_lamda` **does** have a real, clean, monotonic
effect specifically in the *late-period* regime (after land-use activity
naturally freezes, ~day 360+ in the tuned combo — see §5): it controls the
sign of a persistent small daily wage drift via the `1/lamda` exponent in
the `income_ratio` formula. Lower lamda → later-period wage growth
(+3.16% at lamda=0.3), higher lamda → later-period wage decline (-0.55% at
lamda=0.9). Tested at 0.25, 0.3, 0.45, 0.55, 0.57, 0.6, 0.7, 0.9 (plus
0.55 as a repeat-of-baseline sanity check). **`lamda=0.55` was found
closest to flat (+0.24%) and is now the locked-in default** (was `0.95`).
Note: the fine-grained relationship near the zero-crossing (0.55-0.60) is
*not* smooth — small lamda changes there produce disproportionate swings
(same small-sample-chaos pattern as the attempt-rate/success-rate metrics
in §6), so `0.55` was chosen as "best tested candidate," not as a precisely
solved root.

`alfa` was separately **proven** to have zero effect in the late-period
regime specifically: `floor_ratio = (Floor_Size_1/Floor_Size)^alfa`, and
once land-use activity freezes, that base is exactly `1` every day, and
`1^anything = 1` — mechanically incapable of mattering, not just
untested-and-null.

### Migration rate — see §4 items 9 and 10 (two separate, sequential bugs found in the same function)

## 4. All bug fixes, in roughly chronological order, with rationale

Each entry: what was broken, why, the fix. Items 1-8 predate this specific
chat session (found across the whole project); items 9-11 were found and
fixed **in this session**.

1. **Ghost-occupancy in land-use eviction.** Households displaced by a
   building converting to commercial were retried via the `resSearchLen`
   consecutive-failure counter (meant for voluntary moves) instead of
   evicted immediately — let them sit as recorded occupants of a
   now-commercial building for weeks. Fixed: immediate eviction for
   land-use-triggered displacement specifically, matching the confirmed
   original-model behavior (`romansunedited/run_model_eq.m`).
2. **Housing search not filtering by residential zoning.** Candidate asset
   pools didn't check whether the building was still zoned residential.
   Fixed via a shared helper, `filter_residential_assets.m`, applied in
   `find_new_house_same_stat.m`, `find_new_house_yeshuv.m`, and
   `migration_19.m`.
3. **Job-loss mechanism firing on the wrong population.** Matched laid-off
   individuals by *building ID*, unemploying everyone at a multi-job
   building when only one slot should close. Fixed: track the specific
   closed `work_place_id`s (`closed_wp_ids_today`) and match individuals by
   their own workplace-ID column.
4. **`JobsPerM_comm` hardcoded to Ashkelon's value** (`0.007790361`) in two
   places in the land-use module. Fixed: restored dynamic loading from
   `TVR\model parameters.csv` (the original model's own mechanism, which
   had regressed to a hardcoded literal).
5. **`commute_outside` hardcoded to Ashkelon's value** (`0.778038196`,
   literally commented "Ashkelon commuting 99 probability"). Fixed: use
   Tiberias's real rate (`0.246`) from `TVR/commuting.xlsx`, as a named
   `commute_outside_rate` parameter.
6. **`commuting.xlsx` loading the wrong city's data.** Root-level
   `commuting.xlsx` actually contained a different settlement's data (7100,
   not Tiberias's 6700). Fixed: load `TVR\commuting.xlsx` instead. Same bug
   class as an earlier `sas_national.xlsx` fix.
7. **`inOutRatio` misused as an annual growth rate** (migration bug #1 —
   see item 9 below for the fuller writeup, and item 10 for a *second*,
   independent bug in the same replacement code found this session).
8. **`SA_LOCAL` metric checking a column that can never hold the value
   it's testing for.** (Same root cause as item 8 below — found and fixed
   in this session, listed here for chronological completeness within the
   bug list; see item 8's full writeup which follows immediately.)

   *(Renumbering note: the two items above labeled 7 and 8 are the same
   items detailed fully as 9 and — see below — this list continues in
   strict chronological order from here for the fixes made **in this
   session specifically**:)*

9. **`inOutRatio` misused as an annual growth rate** (`migration_19.m`).
   A dimensionless in/out-migration ratio (`sas_national.xlsx` column,
   ~0.44–2.11 across SAs) was used directly as `x = inOutRatio/365`,
   multiplied by vacant-asset count, to determine daily new-household
   arrivals. This produced a model-implied population growth of
   **~23%/year**, vs. real Tiberias census data (`TVR/growthrates1.xlsx`)
   averaging **~1.1%/year** — a 21x overshoot. **Fix**: derive real per-SA
   annual growth rates from that census data (new file
   `TVR/real_growth_rates.csv`), apply them to the model's *current
   household count* in each SA (not vacant-asset count, which is now only
   a cap on how many new households can actually find housing), clip
   negative real rates to 0 (the function only ever adds households; real
   decline comes through existing eviction/departure pathways elsewhere).
10. **A second, independent bug in the same replacement code**, found
    later this session while investigating why population looked flat even
    after fix #9. `families = round(normrnd(expected_new, expected_new/3))`
    — for the realistically small `expected_new` values this produces
    (mostly 0.01–0.25/day per SA), the standard deviation is so tight
    relative to the mean that `round()` essentially **never** crosses 0.5,
    so real arrivals were ~always zero regardless of the (now-correct)
    rate. Confirmed via a diagnostic trace: `families_precap==0` for every
    SA on every day of a 760-day run — literally zero migration arrivals
    city-wide despite `real_growth_rate` correctly being positive for most
    SAs. **Fix**: replaced with `poissrnd(expected_new)` — the standard,
    correct way to convert a small expected rate into a random discrete
    count. **Validated**: 373 arrivals over 760 days (vs. 0 before), net
    population growth annualizing to **1.00%/year**, matching the real
    ~1.11%/year target almost exactly. This is currently **uncommitted**
    (see §0).
11. **`SA_LOCAL` metric checking a column that structurally can never hold
    the value it tests for.** The formula checked
    `Individuals_data(:,12)==99` to detect "works outside the city," but
    whatever function assigns jobs (`find_job_1.m`) sets that column to a
    fixed "employed" value (`2`) for *both* local and outside-city hires —
    the outside-city flag actually lives in a different column
    (`building_work_place`, col 15). Column 12 structurally can never equal
    99, so the metric was permanently pinned at exactly 1.0 regardless of
    real dynamics — this is what tipped off the whole investigation (see
    §5 "how this got found"). **Fixed**: read the local/outside distinction
    off col 15 instead. This was committed (`9b078e7`).
12. **"Add people to working market" applying the status change to the
    wrong set.** Correctly computed a probability-scaled sample size `S`
    and drew a random sample `P` of that size from the eligible pool `F` —
    then applied the status change to the *entire pool* `F` instead of the
    sample `P`. This dumped every eligible non-worker into active job
    search whenever the local economy signaled tightness
    (`income_ratio>1`), creating an artificial post-warmup unemployment
    backlog that took ~50 days to drain and then never recurred at
    meaningful scale (confirmed via a diagnostic trace: day-1 push should
    have been 455 people, actually pushed the full eligible pool of
    12,676). **Fixed**: `Individuals_data(P,12)=1` instead of `(F,12)`.
    Committed (`9b078e7`).
13. **Non-ASCII characters** (`×`, `±`) in `run_model_eq.m`/`earth_quake.m`
    caused MATLAB "Invalid text character" errors under `-batch` — found
    while chasing what turned out to be a different, unrelated cause
    (a throwaway test script named with a leading underscore, which isn't a
    valid MATLAB identifier). Both fixed regardless (`x`, `+/-`).
14. **Concurrency-path fix** (not a correctness bug in model dynamics, but
    a real data-integrity hazard). `run_earthquake_setting.m` wrote its
    intermediate output and its temp scenario-tag-stash file to fixed,
    non-unique paths — two `matlab -batch` processes running concurrently
    would race on both and silently cross-contaminate each other's saved
    output (confirmed twice this project: one process's run ends up saved
    under the other's scenario tag/parameters). **Fixed**: both paths are
    now suffixed with `run_uid` (`sprintf('pid%d', feature('getpid'))`,
    the OS process ID), obtained once per invocation and threaded through
    both the script's own save call and the wrapper's copy/rename/cleanup
    step. **Validated** by deliberately launching two runs with different
    parameters back-to-back so they'd genuinely overlap — both came back
    with correct, non-cross-contaminated parameters. Currently
    **uncommitted**. This is what unlocked running multiple sweep configs
    concurrently later in the session (previously everything had to be
    strictly sequential).

Items 9-14 above are also written up for the sibling Ashkelon project
(`modellab/`) in `BUGFIXES_FOR_MODELLAB.md` in this same folder — that
document flags which of these are universal logic bugs worth checking for
in modellab's code vs. which are Tiberias-specific data recalibrations
that don't transfer directly.

## 5. Performance work (vectorization) — no behavior change, all validated bit-identical

Done after Parallel Computing Toolbox was installed this session, purely
for speed (not correctness — these were already-correct but wastefully
implemented loops). Each was validated by computing old and new logic
side-by-side on live simulation data across a 100-day test run (gated
behind a temporary boolean flag), confirming exact match, then deleting the
old code path. Committed (`9b078e7`):

- **Land-use percentile ranking**: was a per-candidate-building loop
  calling `prctile` fresh for every candidate, then linearly scanning 100
  bins by re-testing membership against the *entire* base salary array
  just to read its own last element — O(candidates × 100 × buildings) of
  pure waste. Replaced with a single batched matrix computation across all
  candidates at once.
- **`MVB30` visit ranking / `building_average_salary` ranking**: same
  100-iteration-scan-per-row pattern, replaced with a single vectorized
  rank-count (`sum(P(1:100) <= value)` per row, all rows at once via
  broadcasting).
- **SA-metrics block**: a loop over every SA re-scanning the *entire*
  Assets/Build_Data/Work_places/Individuals_data/HH_data arrays from
  scratch for every one of ~25 metrics (~20 SAs × ~25 metrics of redundant
  full-array filtering, every `sa_update_every` days) — replaced with
  precomputed group indices + `accumarray`. The non-metric parts of that
  same loop (building-value mutation, price updates, which are
  order-dependent, not a pure aggregation) were left as a smaller residual
  per-SA loop.

**How the wage-decline investigation (§3's `wage_lamda` finding) actually
got found**: started from the user asking why "Mean Workplace Outcome"
looked like log growth instead of the reference paper's exponential shape.
Traced to: workplace count and wage both rise fast early then *plateau and
slowly decline* after land-use activity naturally freezes (~day 360 in the
tuned combo — once the easy high-scoring buildings have all converted,
there's nothing left to convert). That plateau-then-decline led to
tracing the wage-adjustment mechanism specifically in the frozen/quiescent
period, which is what surfaced the `wage_lamda` sensitivity **and**,
along the way, both migration bugs (population also looked suspiciously
flat, which is what prompted checking `migration_19.m` in detail) and the
`SA_LOCAL`/labor-market metric bugs (§4 items 11-12, found while checking
why other metrics looked "too clean" — exactly 1.0 or 0.0 — during the
same investigation).

## 6. Metric/tracking changes

- **`Metric_Track`** (per-step, single-replicate tracking array,
  `nan(steps, N)`) was 23 columns at the start of this session. Now 41,
  added incrementally this session (all **uncommitted**):
  - Cols 1-23: pre-existing (timestep; SA/building service ratio,
    possible-assets, attempt-rate, success-rate — each elderly-vs-non-elderly
    pair; population elderly/non-elderly).
  - Cols 24-25: **young-old / old-old population split**, added to answer
    "why is population flat" with more granularity than the combined
    elderly count. `HH_data(:,5)` encodes `0`=non-elderly, `3`=young-old
    (65-69), `6`=old-old (70+) — confirmed by direct inspection (only
    those three values ever occur, and 3+6 sums exactly to the pre-existing
    combined elderly column).
  - Cols 26-41: young-old/old-old versions of the remaining 8 families
    (SA/building service ratio, normalized possible assets SA/city,
    attempt rate SA/city, success rate SA/city) — added when the user
    asked to see the 3-way split across *all* the metric-change plots, not
    just population. The pre-existing elderly-combined columns (2,4,10,11,
    14,15,16-19,20-23) are **unchanged in meaning**.
  - This required changing `Asset_Avail` column 2's semantics: it used to
    store a boolean `isElderly` flag (written in `find_new_house_same_stat.m`
    and `find_new_house_yeshuv.m`); now stores the actual age-group code
    (0/3/6). Anywhere that used to check `Asset_Avail(:,2)==1` for
    "elderly" now checks `>=3` (matches both 3 and 6) to preserve the old
    combined semantics exactly; `==0` (non-elderly) is unchanged since 0
    means the same thing either way.
  - **Validated**: population sanity check (`elderly == young_old +
    old_old`, max abs diff `0.0`), and spot-checked that young-old/old-old
    values for the Asset_Avail-derived families (attempt/success rate) show
    real, sensible non-NaN data with the expected relative sample sizes
    (young-old subgroup larger → more non-NaN days than old-old).
- **`SA_LOCAL`** (an `SA_*` variable, separate from `Metric_Track`) — see
  §4 item 11. Committed.
- **Small-sample noise in attempt-rate/success-rate/normalized-possible-assets**:
  these are genuinely computed correctly but are extremely noisy at daily
  resolution — on most days only 1-3 households (of any subgroup) attempt
  a move citywide, so e.g. success rate literally only takes values like
  `{0, 0.5, 0.67, 0.8, 1.0}` (ratios of tiny integers) and normalized
  possible-assets can spike to a single SA's entire asset count when n=1.
  **Not a bug** — confirmed by direct inspection of the raw daily values.
  Fixed the *plotting* (not the underlying data) with a 30-day rolling
  average overlaid on a faint raw-data line, in
  `analysis_scripts/plot_sim_results.py`.

## 7. Analysis tooling changes (`analysis_scripts/plot_sim_results.py`)

Pre-existing script, `compare` mode used throughout this session:
```
python plot_sim_results.py compare --scenario NAME1 path1.mat --scenario NAME2 path2.mat --out outdir
```
Produces per-`SA_*`-variable plots + a combined PDF (via `abm_analysis.py`)
**and** `metric_track_comparison.png` (the elderly/age-group breakdown).
Changes made this session, all **uncommitted**:
- 30-day rolling-average smoothing overlay for the noisy small-sample
  families (see §6).
- 3-way (non-elderly/young-old/old-old) breakdown for all 9 `Metric_Track`
  panels (was elderly/non-elderly for 8 of them, population-only 3-way
  before that).
- **Visual encoding redesigned** per explicit user request ("lines more
  distinct"): color now = age group (fixed: blue=non-elderly,
  orange=young-old, red=old-old, consistent across every panel and every
  scenario), linestyle = scenario (cycles through solid/dashed/dotted/
  dash-dot). Old scheme was color=scenario + linestyle=elderly/non-elderly,
  which didn't scale well once there were 3 groups.
- Graceful fallback for older `.mat` files that predate the extended
  `Metric_Track` columns (skips that scenario for that family with a
  console note, rather than erroring).

## 8. Known-open items / natural next steps

- §1's svc_filter-off vs. baseline detailed comparison (numbers generated,
  not yet analyzed/written up).
- Whether to commit the currently-uncommitted work (§0) before continuing.
- `wage_lamda=0.55`'s late-period zero-crossing is only bracketed
  (0.55-0.60), not precisely solved — the fine-grained relationship there
  is noisy, not smooth (see §3). Further precision-chasing was explicitly
  judged not worth it, but worth knowing if it comes up again.
- `BUGFIXES_FOR_MODELLAB.md` in this folder is a ready-to-use handoff for
  a separate chat working on the sibling `modellab/` (Ashkelon) project —
  point that chat at it rather than re-deriving.

## 9. File index (touched this session)

Production code: `run_model_earthquake.m`, `run_earthquake_setting.m`,
`migration_19.m`, `find_new_house_same_stat.m`, `find_new_house_yeshuv.m`,
`find_new_house_sa_score.m` (unchanged, checked only), `filter_residential_assets.m`
(pre-existing helper), `run_model_eq.m` / `earth_quake.m` (encoding fix only).

Data: `TVR/real_growth_rates.csv` (new, this session).

Analysis: `analysis_scripts/plot_sim_results.py`,
`analysis_scripts/abm_analysis.py` (used, not modified),
`plot_baseline_macro_all.py` (older, superseded by `plot_sim_results.py
compare` for most purposes this session).

Many throwaway `run_test_*.m` / `run_late_*.m` / `run_validate_*.m` /
`run_diag_*.m` scripts exist in this folder from this session's testing —
none are meant to be permanent, all are safe to delete if the folder needs
cleaning up. Their corresponding `.mat` outputs are in `earthquakeF/`.

---

# §10. THE FLOORSPACE VARIANT + EARTHQUAKE-SHOCK FRAMEWORK

Everything in this section postdates §§1-9 above (commit `f32827f`) and, as
of this writing, is **almost entirely uncommitted** — a huge amount of work
(a whole new model fork, an earthquake-shock/shelter/reentry mechanism, a
land-use retuning, a 47-column `Metric_Track`, and a full statistical
reporting pipeline) sits either as uncommitted changes to already-tracked
files or as brand-new untracked files. Git log/diff will show almost
nothing for this stretch (three small commits: `2b02e68`, `e5cf18c`,
`67af74f` — the latter two bundle the entire floorspace fork into one WIP
commit). **Read the actual code and its comments, not git history, to
understand this era of the project** — the comments here are unusually
detailed and explain *why*, not just *what*.

Whoever picks this up should decide whether/how to commit this working
tree before continuing — as of this writing that decision has not been
made (same open question §0 raised for the pre-floorspace work, still
unresolved and now much larger in scope).

## 10.0 Orientation

Two parallel model lineages now coexist in this repo:
- **Count-based** (pre-existing): `run_model_earthquake.m` /
  `run_earthquake_setting.m` — §§1-9's subject, service ratio computed by
  counting neighbor buildings.
- **Floorspace-weighted** (this section's subject):
  `run_model_earthquake_floorspace.m` / `run_earthquake_setting_floorspace.m`
  — service ratio computed from summed building floorspace instead of
  building counts, plus the entire earthquake-shock mechanism.

The floorspace script's fork chain: `nextchangesfortracker.m` →
`nextchangesfortracker_shockpolicies.m` (added subsidy/shelter toggles,
gated so shock-off behavior is unchanged) → `run_model_earthquake_floorspace.m`
(swapped the iterative multi-wave `rocket_attack2` shock delivery for a
one-time `earth_quake()` trigger at `shock_step`).

## 10.1 What "floorspace" means, and the pricing bug it exposed

The original model measured a building's/SA's "service ratio" by **counting**
commercial vs. residential neighbor buildings within radius, regardless of
size. The floorspace variant sums each building's actual **floorspace**
instead (`Build_Data` col 25 — footprint × floors, or summed asset floor
areas once assets exist) and uses that as the numerator/denominator. This
is a real behavioral change, not just a different reported number: the
result (`Build_Data(:,19)`) feeds `building_score.m` and `new_house.m`'s
elderly weighted asset-pick directly.

Two metrics now exist side by side, deliberately kept independent:
- **Service ratio** (`Build_Data` col 19 / `stat_data` col 5-6) —
  floorspace-weighted, drives elderly search behavior. Computed by the new
  `building_service_ratio_floorspace.m` (forked from `building_service_ratio.m`
  specifically because col 19 is read by decision logic, not just reported —
  a parameter toggle wasn't safe here). Includes a documented judgment call
  for the zero-residential-neighbor fallback: normalizes against the
  average usage==1 building's own floorspace rather than the original
  count-based `/10` constant, flagged as "expected to be a rare edge
  case... revisit if it turns out not to be rare."
- **Service density** (`Build_Data` col 26 / `stat_data` col 7-8) —
  floorspace over a **fixed land area** (`pi*radius_m^2`), reporting-only,
  computed by the new `building_service_density.m`, feeds nothing. Its
  header states the point explicitly: "immune to the shock's effect on
  residential stock — destroying housing nearby cannot move this metric at
  all, only destroying commercial buildings can." This is the metric behind
  every "service density" column/plot referenced elsewhere in recent
  reports and in this chat's own recent answers (e.g. the 45-85 band's
  residential/commercial stock impact, and the day100/day300 shock
  comparisons) — it was chosen for shock-effect reporting *because* it's
  immune to the exact artifact described next.

**Pricing bug found and fixed this era**: `ass_price.m` divides
`Build_Data(:,19)` (now floorspace-weighted) by `stat_data(:,2)` (still
building-count-based, from the untouched `stat_service.m`) — silently
mixing units and corrupting every asset's initial price/monthly cost, and
therefore affordability filtering, for the entire run. This was present
"in every floorspace-driven run this session prior to this fix." Fixed by
overwriting `stat_data(:,2)` in place with a floorspace-weighted
(commercial+public)/residential ratio computed per-SA from `Build_Data(:,25)`
— `stat_service.m` itself is untouched, so the count-based script still
gets count-based col(2). **This is why many scenario families in
`analysis_scripts/reports/` exist in two forms — a larger-n pre-fix
version and a smaller-n `_FIXED_n5` version — treat any non-`_FIXED`
floorspace result as stale/superseded once a FIXED counterpart exists.**

## 10.2 Earthquake shock mechanism

- `shock_step` (default 900 = never fires unless overridden) triggers a
  one-time `earth_quake()` call. **Gotcha**: for any run with `steps=900`,
  `shock_step` must be explicitly overridden (e.g. to `9999`) to get a true
  no-shock baseline, or the shock fires on the run's last day.
- Requires `TVR\earthquake_damage.csv` — a path bug (missing the `TVR\`
  prefix every other data load in this file uses) was fixed; "never caught
  before because no run prior to this had shock_step reachable within its
  step count."
- **Usage-blind destruction fix**: `earth_quake.m` picks damaged buildings
  regardless of type, but only residential buildings' usage actually zeroed
  out before this fix (non-residential buildings have zero `Assets` rows,
  so `find_empty_buildings.m` never marked them empty) — "destroyed
  commercial/industrial/public buildings kept counting as active service
  providers... indefinitely." Fixed by zeroing `Build_Data(:,3)` uniformly
  for every destroyed building, capturing pre-shock usage into
  `destroyed_B(:,4)` first (so it can be restored on recovery).
- **Recovery**: independent per-building daily Bernoulli draw,
  `RECOVERY = 1-(1-0.3135)^(1/365)`, derived from real reconstruction-
  timeline data (31.35% of residential housing recovers within 1 year),
  ported and day-rescaled from `modellab/run_model_earthquake_shelteroverflow.m`.
  Replaces the old deterministic shared-countdown mechanism ("every
  destroyed building recovered at exactly the same step count regardless
  of size... producing a step function rather than a curve"). Recovered
  residential buildings revert to their pre-shock usage type — fixing what
  the code calls "the actual bug behind SA_RESIDENT never recovering after
  a shock." Non-residential buildings stay `usage=0` permanently by design.
- **Shelter**: `displaced_shelter` toggle (default 1). `assign_shelter_sa`
  places destroyed households at shock time; `release_shelter_capped`
  releases them as their home recovers, or force-releases at
  `max_shelter_duration=120` days ("placeholder — not yet sensitivity
  tested"). Sheltered households' service/density metrics reflect the
  shelter's location, not the destroyed home, until released.
- **Staggered vs. non-staggered reentry**: `use_staggered_relocation`
  (default 1). Staggered mode draws each displaced household once as
  "slow" (prob `relocation_w_slow=0.3947`) or "fast" at shock time, then
  each day draws eligibility at `relocation_p_slow=0.01394` or
  `relocation_p_fast=0.20199` — calibrated from **2015 Nepal earthquake IDP
  data**. Non-staggered mode retries every displaced household daily until
  it succeeds. Setting `relocation_p_slow == relocation_p_fast` collapses
  the mixture to a flat daily rate — used by the `shock_flat1pct` scenario
  family (`relocation_p_slow=relocation_p_fast=0.01`) to isolate whether a
  simple realistic daily rate, vs. the Nepal mixture, measurably changes
  how fast displaced households find housing.
- **Shock-day relocation blocking** (the most recent fix in this file, and
  the one that resolved a "why does density go UP right after the
  earthquake" investigation — see §10.6): no household of any kind — shock-
  displaced or an ordinary background mover — relocates on the shock day
  itself. This gives a clean "destruction happened, nobody has moved yet"
  snapshot. Newly-destroyed households' first eligibility check is deferred
  to the day *after* the shock. Non-staggered mode carries them over via a
  new `delayed_shock_hh` persistence variable (added to the `clearvars`
  keep-list so it survives the `run()` workspace boundary); staggered mode
  needs no carry-over since `pending_relocation` already has them queued
  and is simply left untouched for one extra day. Ordinary background
  movers are separately suppressed the same day via `moving_HH=[]`
  overrides at both the K=2 and K=3 `who_is_moving` call sites.
  **Root cause this fixed**: without it, displaced households (who started
  below-average on service metrics) could get reassigned into
  average/better buildings before the shock-day metric was ever recorded,
  masking the true (negative) immediate destruction effect and making it
  look like density *increased* right after the quake.

## 10.3 Land-use conversion band — the 45-85 validated combo

`lu_change_rank_lower`/`lu_change_rank_upper` (defaults 45/85, widened from
an earlier 60-80) gate `Change_LU`: every `lu_update_every` step, a
candidate building's rank-diff score (visits-percentile rank minus
salary-percentile rank) has to fall strictly inside this band to flip from
residential to commercial. It's a one-way valve — nothing in this pathway
converts commercial back to residential. `new_jobs_rank_thresh=20` /
`lost_jobs_rank_thresh=-100` are locked in alongside it as part of the same
validated combo (never varied independently of the band in any band test).

**The full rationale, from a 10-replicate 95% CI check** (quoted from
`run_earthquake_setting_floorspace.m`'s header comment, mirrored in
`run_model_earthquake_floorspace.m`):

> Band 45-85 lets `SA_JOBS` (occupied-job share) reach a genuine,
> reproducible saturation point (1.0000 [1.0000,1.0000] by day 550, vs.
> 60-80's 0.9480 [0.9456,0.9504] still climbing), which lets mean wage
> actually plateau instead of drifting indefinitely (8796.7 [8767.3,8826.1]
> at day 550). **Trade-off**: population ends essentially flat at day 550
> (17450.4 [17424.9,17475.9] vs. 60-80's continued growth to 17680
> [17664,17697]), and workplace count overbuilds substantially (28220.5
> [27729.6,28711.4] vs. 60-80's ~21686).

This was chosen **deliberately**, accepting the population/workplace
trade-off in exchange for genuine job-market saturation. (An earlier round
of this same CI check used a since-removed `job_search_breadth`
random-shuffle mechanism that turned out not to match the true original
matching logic and gave meaningfully different numbers — the CI above is
from the corrected matching logic and is the one to trust.)

Measured concrete effect on building stock under this band (from an actual
completed 900-day no-shock run, `baseline_jpm3x_900day_floorspace_rep1`,
computed live in this chat, not from a stored report): residential stock
2,466→2,287 (-7.3%), commercial/service stock 990→1,111 (+12.2%) over 900
days, conversion front-loaded (commercial hits its final count by roughly
the run's midpoint, then flat) — see this chat's own answer for the full
table if reproducing.

`lu_jobs_per_meter` (default `0.040197164`, 4.5x Tiberias `JobsPerM_comm`)
seeds jobs *after* a building converts; `lu_potential_jobs_per_meter`
(default `0.017865406`, 2.0x) feeds the ranking that decides *whether* it
converts — tested independently of each other, same validated-combo
status.

## 10.4 `elderly_search_mode` — modes 0-6, and a real bug fix this era

Full definitions live in `find_new_house_sa_score.m` (lines 1-61):

| Mode | Mechanic |
|---|---|
| 0 | Legacy/off — standard threshold, one plain pick. True no-behavioral-change control. |
| 1 | Same as 0, but final asset pick weighted toward higher building-service-ratio for elderly (old-old leans harder). |
| 2 | **Finalized methodology.** SA-level hard filter replaces the threshold for elderly (only SAs with SA-service-ratio ≥ current qualify); one destination SA weight-picked among qualifiers; asset within picked plainly at random. |
| 3 | Standard threshold picks eligible SAs; destination SA weight-picked among them; asset within ALSO weight-picked by building-level ratio. |
| 4 | Same as 3 but asset-within picked plainly at random — isolates "does concentrating into better SAs help on its own." |
| 5 | Same as 3/4 with a stronger exponent (young-old squared, old-old cubed vs. mode 3's linear/squared). |
| 6 | Same hard SA-level filter as mode 2, but SA choice is plain random for both groups — age differentiation only at asset-selection. |

`elderly_search_mode=2` remains the finalized default for the floorspace
model too (same rationale as §§ pre-existing HANDOVER content: largest,
most significant SA-service-ratio gain for both young-old and old-old,
n=10, p<1e-7 both groups vs. baseline over a 760-day average; `eld_movef`
tested layered on top and rejected — every reduction tested delayed
young-old's SA-service crossover point (~day 120-180) enough to drag the
full-run average back to non-significance).

**Bug fix this era**: `svc_filter=1` is mode 2/6's within-SA hard floor,
not an independent toggle safe to leave at 0 — but every
`run_earthquake_setting*.m` call this session had been explicitly passing
`svc_filter=0`, meaning **every `elderly_search_mode=2` earthquake run so
far was silently missing its within-SA filter component.** Now enforced
unconditionally in `run_model_earthquake_floorspace.m`:
```matlab
if (elderly_search_mode==2 || elderly_search_mode==6) && svc_filter~=1
    svc_filter=1;
end
```
Any mode-2 result generated before this fix landed should be treated as
suspect for anything the within-SA filter would affect.

`mode0`/`mode2` in scenario filenames and the `SCENARIOS` dicts (§10.7)
mean exactly this `elderly_search_mode` value — confirmed directly from
code, not assumed. Nothing to do with staggered/shelter toggles.

## 10.5 `Metric_Track` now 47 columns; other tracking/helper changes

Cols 1-23 unchanged from §6's pre-existing description. New this era:

| Col | Metric |
|---|---|
| 24-25 | Young-old / old-old population |
| 26-29 | SA / building service ratio, young-old / old-old |
| 30-33 | Normalized possible assets SA/city, young-old / old-old |
| 34-37 | Attempt rate SA/city, young-old / old-old |
| 38-41 | Success rate SA/city, young-old / old-old |
| **42-44** | **SA service density**, non-elderly / young-old / old-old (from `stat_data` col 8 — land-area density, reporting-only) |
| **45-47** | **Building service density**, non-elderly / young-old / old-old (from `Build_Data` col 26) |

`Asset_Avail` col 2 now stores the actual age-group code (0/3/6), not a
boolean — anywhere that used to check `==1` for "elderly" now checks `>=3`.

New small helper files: `building_service_density.m` (§10.1),
`building_service_ratio_floorspace.m` (§10.1), and
`filter_by_building_service.m` — a shared candidate-pool filter for
`svc_filter`, applied uniformly to within-SA *and* out-of-SA pools (this
generalizes the within-SA-only `svc_filter` from the pre-existing
CLAUDE.md/HANDOVER description; the out-of-SA application is specifically
what `elderly_search_mode==1` uses it for).

`migration_19.m`: the two migration bugs already documented in §4 items
9-10 are unchanged. What's new: an `HH_MOVE_TRACK` column extension (6→8
cols, adding OldOld_Count and a 3-month SA snapshot slot, matching the
Metric_Track 3-way split) and a col(18) job-search-acceptance-threshold
draw fix for newly-unemployed migration arrivals (same bug class as §4
item 12, applied to a code path that item didn't originally cover).

`Metric_Change` and the `clearvars -except` keep-list were extended to
match — see the file itself for the full current keep-list if you need to
know exactly what survives into a saved `.mat` (it now also persists
several one-time diagnostic snapshot arrays — see §10.9).

## 10.6 Shock-report methodology: reference points and significance testing

Built out this session in `analysis_scripts/build_full_timepoint_report_v2.py`
and `build_standard_report_v2.py`, in direct response to the "why does
density go up right after the earthquake" investigation (§10.2's shock-day
fix was the other half of that investigation's resolution):

- **Two different reference points, depending on metric type.** "Smooth"
  metrics (SA/building service level and density — always defined, one
  value per day) use: **Immediate effect** = day-(shock_step-1) vs.
  day-shock_step (a true single-day before/after snapshot); **Recovery** =
  final value vs. the 30-day trailing average ending the day before the
  shock (a more robust "normal conditions" baseline than any single day).
  "Sparse" metrics (normalized possible assets, attempt/success rates —
  only defined for households that actually attempted a move that specific
  day, so single-day values can be noisy or `NaN`) keep the original
  multi-day trailing average (days 1 through shock_step-1) as the reference
  for *both* columns instead.
- **Long-term change** = final value (shock scenario) vs. final value of a
  matched no-shock baseline **re-run to the identical duration**, so both
  "final" values land on the same simulation day. This requires an actual
  matching baseline run to exist (e.g. `baseline_jpm3x_900day_floorspace`
  for a 900-day shock scenario) — without one, this column reads `n/a`.
- **Why day-(shock_step-1)/30-day-avg instead of a longer pre-shock
  average**: a longer trailing average gets diluted by organic pre-shock
  growth (the land-use module is still active before the shock), which was
  independently masking/flipping the sign of the true immediate effect —
  this was the second of the two artifacts behind the "density increases
  right after the earthquake" illusion (the first being the shock-day
  relocation issue §10.2 fixed).
- **Significance testing**: Welch's two-sample t-test, applied at the
  **replicate level** (n replicate-level values per group, not per-
  household — avoids pseudo-replication/non-independence within a single
  simulation run), via `scipy.stats.ttest_ind(..., equal_var=False)`. Added
  to: the full-timepoint report's Table A (elderly-vs-NonElderly) and Table
  B (Displaced-vs-NonDisplaced), and the standard report's top table and
  Percent-change section (elderly groups vs. NonElderly). At n=5, raw-value
  comparisons are significant in the large majority of cells; %-change
  columns have visibly lower power (higher variance across only 5
  replicates) — worth more reps if a specific %-change cell's significance
  matters for the thesis.
- `shock_step` is now a configurable field in both scripts' `SCENARIOS`
  dict entries (was hardcoded to 100) — needed once the day-300 scenario
  (§10.7) existed.

## 10.7 Scenario catalog — what's actually been run

Naming convention: `run_<baseline|earthquake|scenario>_<dayNNN>_<band|jpm|
radius modifiers>_<mode0>_floorspace[_repN].m`, each a short wrapper
calling `run_earthquake_setting_floorspace(...)`. Dozens exist in the repo
root; not all are catalogued here — the ones with a `SCENARIOS` dict entry
(and therefore a generated report) are the ones that matter.

**Locked-in defaults unless a scenario name says otherwise**: band 45-85,
`elderly_search_mode=2`, `lu_jobs_per_meter`=4.5x/`lu_potential`=2.0x,
`service_radius_m=400`, no shelter override, staggered reentry off unless
named `staggered`/`nostagger` explicitly varies it, `svc_filter` auto-
enforced per §10.4.

**Major axes tested** (each combinable with mode0/mode2, and with pre-fix
vs. `_FIXED` pricing per §10.1):
- **Shock timing**: day100 (760-day run) vs. day300 (900-day run, with a
  matched 900-day no-shock baseline built specifically for it).
- **Reentry**: `nostagger` (same-day rehousing attempts) vs. `staggered`
  (Nepal-calibrated mixture) vs. `shock_flat1pct` (flat 1%/day, isolates
  the mixture's effect from a simple realistic rate).
- **Land-use band**: default 45-85 vs. `band60_80` (the pre-this-era
  value, re-tested here for comparison) vs. a wider `band45_85`/`50_85`
  exploration family on the count-based (non-floorspace) sibling scripts.
- **Jobs-per-meter multiplier**: default 4.5x/2.0x vs. `jpm3x` (3.0x) vs.
  `jpm2_5x` (2.5x/2.5x, paired with `radius500`, `resSearchLen=14`).
- **Service radius**: default 400m vs. 500m (`radius500` family, an older
  count-based-model exploration predating this fork — `run_scenario_
  jpm2_5x_radius500.m`'s own comment calls it out as reusing "the prior
  'radius500' experiment").
- **`resSearchLen`**: default (`round(steps*30/760)`, i.e. 30 for a 760-day
  run) vs. 14, under jpm3x (`reslen14`/`reslen30` pair).

**Standing "do not re-run" list** (explicit user instructions this
session, still in force): resSearchLen (reslen14/reslen30) changes, the
radius500 changes, and `band60_80` — the user killed a `band60_80` batch
mid-run "for a reason" and does not want it re-launched without being
asked again explicitly. Respect this unless the user re-opens it.

Report output lives under `analysis_scripts/reports/<scenario>/table.md`
(merged standard + full-timepoint report) — see that directory listing for
the full set of scenarios that have actually been analyzed to date; cross-
reference against the `SCENARIOS` dict in both `build_full_timepoint_
report_v2.py` and `build_standard_report_v2.py` before assuming a name
means what it looks like it means.

## 10.8 Analysis tooling

- `analysis_scripts/build_standard_report_v2.py` /
  `build_full_timepoint_report_v2.py` — the current (v2) report builders;
  see §10.6 for what's new in them this era. Both keyed off a `SCENARIOS`
  dict literal near the top of each file — that dict is the actual source
  of truth for "what scenario means what config," not the filename alone.
- `analysis_scripts/export_full_timepoint_csv_v2.py` — exports the same
  three tables (A/B/C, no std-dev columns) to one `.xlsx` per scenario
  (3 sheets), superseding an earlier CSV-only version.
- `analysis_scripts/plot_sim_results.py` `compare` mode — unchanged in
  purpose from §7's description (2+ named `.mat` files, produces per-`SA_*`
  plots + a combined PDF + `metric_track_comparison.png`), gained a
  `--color NAME COLOR` override and zero-fill-day filtering for
  `sa_update_every>1` runs this era. Note: `compare` mode takes exactly one
  `.mat` file per scenario (no built-in ensemble averaging across
  replicates) — when comparing an n=5 scenario pair, the established
  practice this session was to compare `rep1` of each as representative,
  not an average; extending it to average across reps would be a small,
  not-yet-done addition if that's ever needed.

## 10.9 Open items / unresolved investigations

- **Unresolved hang**: an unconditional `if mod(i,20)==0 || i==1;
  fprintf('[progress] day %d/%d...')` progress marker is still present in
  `run_model_earthquake_floorspace.m`, added after a run hung with no error
  and near-zero CPU for 17+ hours with no way to tell which day it stalled
  on. Comment says "remove once the hang is understood/fixed" — it hasn't
  been; the underlying cause is still unknown.
- **Two one-time diagnostic blocks still live** in the main script
  (same-day-reassignment check, full-population same-building-vs-moved
  decomposition) from the density-jump investigation. Some hypotheses are
  marked "already ruled out" in their own comments, and the investigation's
  actual resolution (§10.2 + §10.6) has landed, so these read like cleanup
  candidates now rather than active instrumentation — worth asking the user
  before deleting, since they may still want the diagnostic snapshots for
  the thesis writeup.
- **`run_model_earthquake_shelter_routines.m`**: a separate, NOT-yet-
  reconciled fork exploring different shelter-routine-recompute behavior
  (immediate routine recompute for newly-sheltered agents), built on the
  older `nextchangesfortracker_shockpolicies.m` lineage — not integrated
  into the floorspace script. Explicit in-file comment: "Not yet decided
  which behavior is correct for the thesis — keeping both as separate files
  so results can be compared side by side." Live open decision, relevant to
  why this branch is named `sheltering-design-items`.
- **Subsidy policy not exposed as a wrapper argument**: `subsidy_residents`/
  `subsidy_pct`/`w_subsidy_eld` remain hardcoded inside
  `run_model_earthquake_floorspace.m` itself (`subsidy_residents=0`, off by
  default) rather than being `run_earthquake_setting_floorspace.m`
  positional args — unlike shelter/staggered-reentry, which are now
  exposed. `shock_delta_report.py`'s header TODO about this is half-stale:
  the shelter half is done, the subsidy half genuinely isn't.
- **Placeholders not yet sensitivity-tested**: `max_shelter_duration=120`,
  `w_subsidy_eld=0.5`, `subsidy_pct=0.15`.
- §1's old svc_filter-off-vs-baseline write-up (pre-floorspace) is still
  open per §8 — unrelated to this section's work but still unresolved.

## 10.10 File index for this section

Production code: `run_model_earthquake_floorspace.m` (main script, ~2,100
lines), `run_earthquake_setting_floorspace.m` (wrapper, 31 positional
args), `building_service_density.m`, `building_service_ratio_floorspace.m`,
`filter_by_building_service.m`, `migration_19.m` (incremental changes
only), `find_new_house_sa_score.m` (mode 0-6 definitions, unchanged this
era but the canonical reference for §10.4).

Analysis: `analysis_scripts/build_standard_report_v2.py`,
`analysis_scripts/build_full_timepoint_report_v2.py`,
`analysis_scripts/export_full_timepoint_csv_v2.py`,
`analysis_scripts/plot_sim_results.py` (compare mode changes only).

Scenario wrapper scripts: ~100+ `run_earthquake_day*_floorspace*.m` /
`run_baseline_*floorspace*.m` / `run_scenario_*.m` / `run_band*.m` /
`run_wideband_*.m` / `run_jpm_test_*.m` / `run_potjpm_test_*.m` in the repo
root — see §10.7 for which combinations they represent; not individually
indexed here.

Not part of this fork, flagged only because it's easy to confuse with it:
`run_model_earthquake_shelter_routines.m` (§10.9 — separate, undecided
fork), `shelter_policy_extensions_handoff.md` / `shock_policy_handoff.md`
(both actually about the sibling Ashkelon/`modellab` project, despite
living in this folder — not about modelthesis's own shock work).

---

# §11. This chat's additional work — lives in a SEPARATE git worktree

**Read this before assuming anything below is in the main working tree
described in §§0-10.** Everything in this section was done from a
dedicated git worktree at
`C:\Users\allis\Documents\MATLAB\.claude\worktrees\elderly-search-methodology`
(branch `elderly-search-methodology-explore`, branched from commit
`f32827f` on `service-radius-test`), created specifically so this chat's
elderly-search-methodology exploration wouldn't collide with the other
chat's live edits to the floorspace files (§10). Practical consequences:

- **What IS in the main tree**: everything up through commit `f32827f`
  (mode 1-6 implementation, `eld_movef`/`eld_movef_old` split, the
  finalized-methodology defaults in the QUICK REFERENCE box above,
  `standard_report.py`/`shock_delta_report.py`/`run_final_methodology.m`/
  `run_mode6_option.m`) — that commit is on the shared branch, so any
  chat working in the normal `modelthesis/` directory has it.
- **What is NOT in the main tree**: everything described in §11.1-§11.5
  below only exists inside that worktree's own working directory unless/
  until its branch is merged. If you're not explicitly told you're in
  that worktree, assume you don't have it.
- **The worktree's copies of the floorspace-fork files can go stale.**
  Those files (`run_model_earthquake_floorspace.m`,
  `run_earthquake_setting_floorspace.m`,
  `building_service_ratio_floorspace.m`, `building_service_density.m`,
  `filter_by_building_service.m`, `migration_19.m`, `TVR/sa_land_area.csv`)
  were uncommitted in the shared tree when the worktree branched, so they
  had to be copied in by hand — they are NOT tracked by the worktree's own
  git history. Confirmed this actually caused real failures twice this
  session: `migration_19.m`'s `HH_MOVE_TRACK` column count changed
  underneath the copy (crashed `vertcat` mid-run), and
  `filter_by_building_service.m`/`TVR/sa_land_area.csv` went missing from
  the worktree copy entirely between sessions for an unclear reason.
  **Always re-diff the worktree's copy against the current shared-tree
  version before trusting a floorspace run launched from the worktree.**

## 11.1 `standard_report.py` / `shock_delta_report.py` — not the same tools as §10.8's v2 versions

Built in the worktree, independently of (and before this chat was aware
of) `build_standard_report_v2.py`/`build_full_timepoint_report_v2.py`
(§10.8 — the other chat's tools, in the main tree). Overlapping purpose,
different implementation, **not reconciled with each other**:
- `analysis_scripts/standard_report.py <config> [<config2> ...]`: results
  table (SA/building service level, SA/city success rate, normalized
  assets — 6 metrics × 3 population groups, avg±std, significance
  asterisks vs. non-senior within that config) + `Metric_Track` trend
  plots + all 24 `SA_*` macro-economic plots (overview grid PNG +
  one-page-per-variable PDF + individual PNGs). Config name → file-glob
  mapping lives in its own `CONFIGS` dict at the top of the file — edit
  that to add a new config.
- `analysis_scripts/shock_delta_report.py <scenario_pattern> [...]
  [--baseline X]`: compares one or more shock scenarios against a single
  fixed baseline (default `760day_mode2`, i.e. the finalized methodology
  with no shock) — deltas per metric per population group, with
  significance once both sides have ≥2 replicates. Deliberately NOT a
  mode-vs-mode comparison (the methodology is fixed at mode 2; what varies
  is the shock scenario).

Both committed at `f32827f`. **Before reaching for either report system,
check which one actually has current scenario/config coverage for what
you need** — they were built by different chats and don't know about each
other's scenario catalogs.

## 11.2 Elderly and commercial-building distribution maps

Ad-hoc matplotlib (hexbin) scripts built inline in chat, not saved as
reusable `.py` files — results were sent as images, the generating code
wasn't preserved. If this is needed again: household/building XY comes
from a building-ID lookup into `Build_Data` cols 1 (ID) / 5-6 (X/Y);
young-old/old-old identified via `HH_data(:,5)` (3/6); commercial
buildings via `Build_Data(:,3)` usage 2-3. Pattern used: 2×2 grid
(age-group × init-vs-final), final panels averaged across all replicates
of a config with a shared color scale (weight each replicate `1/n_reps`
in the hexbin `C` aggregation), and a second pass giving baseline +
modes 1-6 a shared color scale across all 7 so density is comparable
mode-to-mode. Worth turning into a real script under `analysis_scripts/`
if maps become a recurring deliverable — currently they aren't one.

## 11.3 Mode significance ranking — which mode has the smallest still-significant effect

Using Welch's t-test on SA service ratio, each mode vs. baseline (full
760-day per-replicate average, count-based/non-floorspace model, n as
available per mode — see the QUICK REFERENCE box's replicate counts):
**mode 1 has by far the smallest, most marginal significant effect**
(young-old Δ=+0.018, p=0.0017; old-old Δ=+0.019, p=0.029 — the weakest
p-value of any mode, and the only one that would NOT survive a Bonferroni
correction across all 6 modes tested at once). Mode 2 has both the
largest effect size AND the strongest significance (n=10, p<1e-7 both
groups) — consistent with, and additional support for, §10.4's
finalized-methodology rationale. Mode 6 is the next-smallest genuinely
significant effect after mode 1 (p<0.001 both groups) if a "modest but
statistically solid" profile is ever wanted instead of mode 1's borderline
one.

## 11.4 Mode 1 retest under the floorspace model — apparent bug was actually a units mismatch, not a bug

Re-ran mode 1 (already confirmed weak/marginal under the count-based
model, §11.3) through the floorspace fork, to check whether a
floorspace-based service metric changes that conclusion. First result
looked broken: SA service ratio came out ~3.7x higher than the
count-based baseline's, **including for non-elderly** — a population mode
1's weighting mechanism doesn't touch at all, which should be impossible
if the difference were caused by the search-mode behavior itself.

**Root cause, confirmed at the code level (not a bug)**: `stat_data(:,5)`/
`(:,6)` — the SA-level service ratio that both feeds `Metric_Track`'s "SA
service ratio" column AND gates `pref_hh`/`SA_score_old`'s eligibility
threshold — is *also* floorspace-weighted in this fork, not just the
building-level `Build_Data(:,19)` documented in §10.1. The line
`com0 = sum(b0(b0(:,3)>1 & b0(:,3)<4, 25))` sums column 25 (floorspace),
not a building count — easy to misread on a first pass since the
surrounding formula still looks like the same `com/res` pattern as the
count-based version. Floorspace-based ratios run on a structurally
different numeric scale than count-based ones (a single large building
contributes proportionally more than a count-based model would ever
allow), so **a floorspace-model result is not comparable in absolute
terms to a count-based-model result — only within-run (elderly vs.
non-elderly, same units, same run) comparisons are valid across the two
model versions.** Within-run comparison confirmed mode 1 still fails
under floorspace too, on all four available service metrics (SA ratio,
building ratio, SA density, building density) — reinforces mode 2 as the
right choice regardless of which service-measurement convention is used.
Runs: `760day_mode1_floorspace[_seed2-4]` in the worktree's `earthquakeF/`.

## 11.5 550-day, 5-replicate floorspace re-test of all modes — INTERRUPTED, partially done

User requested: baseline + modes 1-6, 5 replicates each, 550 days, no
shock, floorspace model, evaluated with the new density metrics. Status
when the user explicitly said to stop the batch:

| Config | Replicates complete |
|---|---|
| baseline | **5/5** |
| mode 1 | **5/5** |
| mode 2 | **5/5** |
| mode 3 | 2/5 (seed1, seed2 — launched, then stopped by user instruction before seed3-5; confirmed both already stopped via task notification, no process kill was needed) |
| mode 4 | 0/5, not started |
| mode 5 | 0/5, not started |
| mode 6 | 0/5, not started |

Scripts `run_550day_floorspace_<config>_seed<N>.m` (N=1-5) exist in the
worktree for all 7 configs, including the unrun ones — resume by
launching mode3 seed3-5 and modes 4-6's full 5 seeds each if this should
be completed. **Not yet analyzed even for the completed configs** — no
results table or plots have been built from this batch.

## 11.6 `modellab/` (sibling Ashkelon project directory) — Tiberias calibration transfer

Not part of `modelthesis/` at all, but changed by this chat at the user's
request, to make modellab able to run modelthesis's validated Tiberias
calibration. Two sub-findings first:

- **Confirmed `data_for_model_tmine_agesplit70.mat` (modelthesis's init
  dataset) is fully validated** —
  `modelthesis/data_allocation/allocation_validation_report_agesplit70.csv`
  shows 100% `OK`/`INFO` rows (structural integrity, demographics, income
  deciles, cars, labor force — all within a few points of real Israeli
  census reference values), zero failures.
- **modellab has no wrapper function equivalent to
  `run_earthquake_setting.m`** — per-city calibration constants are
  hardcoded inline in a `switch city` block, duplicated across TWO
  separate scripts: `run_model_earthquake.m` and
  `run_model_earthquake_shelteroverflow.m`. This chat initially edited the
  wrong one (`run_model_earthquake.m`) and reverted it after explicit user
  correction — **the actual target for this work is
  `run_model_earthquake_shelteroverflow.m`**.

Changes made to `modellab/run_model_earthquake_shelteroverflow.m`'s
`case 'Tiberias'` block (inside the `switch city` city-configuration
block near the top of the file):

- `commute_outside`: was `NaN` (a TODO placeholder — would `error()` out
  immediately per the file's own `isnan` guard) → **`0.246`**, matching
  modelthesis's validated `commute_outside_rate`.
- `alfa`/`beta`/`lamda`/`delta`: was `NaN` → **`0.3`/`0.8`/`0.95`/`0.75`**,
  matching modelthesis's validated wage parameters exactly.
- `JobsPerM_comm` itself (the base per-city rate, `0.008932703` for
  Tiberias) is unchanged — but see below, it's now consumed differently.
- **Added 4 new `~exist(...)`-guarded override variables**, matching the
  existing `lu_warmup`/`lu_update_every`/`steps`/`shock_step` pattern
  already in the file, so they're settable from a driver script rather
  than hardcoded: `jobs_per_meter_multiplier`, `potential_jobs_per_meter_
  multiplier`, `lu_change_rank_lower`, `lu_change_rank_upper`. Defaults
  (`1`/`1`/`20`/`40`) exactly reproduce this script's ORIGINAL,
  unmultiplied/untuned behavior for every city unless a driver overrides
  them — no other city's runs are affected by this change.
  - `jobs_per_meter_multiplier` and `potential_jobs_per_meter_multiplier`
    are **multipliers on each city's own base `JobsPerM_comm`**, not
    absolute values — deliberately structured this way (rather than
    hardcoding an absolute number) so the same calibration philosophy is
    testable against any city's own base rate later, not just Tiberias's.
  - The two `JobsPerM_comm`-consuming formulas — the potential-conversion
    candidate-scoring step (`pot_sal_for_B`/`workers` block) and the
    actual job-creation step for newly-converted buildings (`New_Comm_B`/
    `workers` block) — previously both reused the exact same
    `JobsPerM_comm` constant with no differentiation between them. They
    now multiply by `potential_jobs_per_meter_multiplier` and
    `jobs_per_meter_multiplier` respectively, matching modelthesis's
    genuinely-separate `lu_potential_jobs_per_meter` vs. `lu_jobs_per_meter`
    split (§10.3).
  - The hardcoded `V_vec>20 & V_vec<40` rank-diff window (same mechanism
    as §10.3's `lu_change_rank_lower`/`upper`, just never previously
    extracted into named variables here) now reads
    `V_vec>lu_change_rank_lower & V_vec<lu_change_rank_upper`.
- **New driver script `modellab/run_tiberias_calibrated.m`**: sets
  `city='Tiberias'` plus modelthesis's validated values
  (`jobs_per_meter_multiplier=3`, `potential_jobs_per_meter_multiplier=2`,
  `lu_change_rank_lower=45`, `lu_change_rank_upper=85` — matching §10.3's
  3x/2x/45/85 combo, NOT the earlier 4.5x/2x combo those defaults
  superseded) then calls `run('run_model_earthquake_shelteroverflow.m')`.
  Copy this file and change the values to calibrate a different city.
- Verified via `checkcode(...)` on both files — zero warnings on any
  edited line.
- **`run_model_earthquake.m`** (the file edited by mistake, then reverted)
  is confirmed unchanged — still has the original Ashkelon-placeholder
  values for Tiberias if anyone runs Tiberias through that script instead
  of the shelteroverflow one. Nothing in this section touches it.

# §12. AGE-SPLIT CORRECTNESS FIX (2026-09-09) — young-old / old-old was being read off the wrong column

**If you are about to launch runs, re-run a sweep, or interpret any result
split by age group, read this section first. It changes numbers.**

Status: **applied to the working tree, NOT committed.** New file
`hh_age_group.m` is untracked. Everything below is live in
`modelthesis/` (the normal working tree, not the §11 worktree).

## 12.1 The bug in one paragraph

The elderly age split (young-old 65-69 vs old-old 70+) was being derived
from `HH_data(:,5)`, reading `3` as young-old and `6` as old-old. That is
wrong. Col 5 is `3 * (number of household members aged 65+)` — a
HEADCOUNT of elderly members, not an age band. The real 70+ information
has always lived in a **different column, col 12**. The two are
independent: a 65-year-old couple gets col5 `6`, and a lone 80-year-old
gets col5 `3`.

## 12.2 The two columns — do not confuse them again

| Column | Values | Meaning | Set in |
|---|---|---|---|
| `HH_data(:,5)` | 0 / 3 / 6 | `3 x (members aged 65+)`. `0`=none, `3`=one elderly member, `6`=two. Correctly identifies **elderly vs non-elderly** via `>=2`, and nothing more. | `data_allocation/create_HH_12_2018.m` (~line 146, its own comment says "3->1 elderly, 6->2 elderly") |
| `HH_data(:,12)` | 0 / 1 / 2 | Number of members aged 70+. Labelled `'number of old-old (70+)'` in `HH_data_P`. **This is the age split.** | `data_allocation/distribute_HH_2019.m` (~line 95), from `old_old_count` built in `create_HH_12_2018.m` |

There is also a per-individual `is_old_old_lookup` (`[ind_id, 0/1]`) saved
alongside, built in `data_allocation/set_Ind_data.m`. Not currently
consumed by the model.

## 12.3 Evidence — measured on `data_for_model_tmine_agesplit70.mat`

```
CROSS-TAB   col5 (0/3/6)  vs  col12 (real 70+ count)
             c12=0   c12=1   c12=2    total
  c5=0       13472       0       0    13472
  c5=3        1892    1067       0     2959   <- was labelled "young-old"
  c5=6         385     489     145     1019   <- was labelled "old-old"
```

- **1452 of 3978 elderly households (36%) were misclassified.**
- 1067 households holding a 70+ member were counted as young-old.
- 385 households with nobody over 70 were counted as old-old.
- True old-old = **1701** households; the old code reported **1019**
  (understated 40%). Overlap between old and new "old-old" sets: only 634.

The comment that previously justified the old reading ("confirmed by
inspection ... 3+6 sums exactly to the elderly count") was not a valid
check — that sum holds under either interpretation.

Note `pref_hh.m` and `SA_score_old.m` were ALREADY correct (they used col
12). So the codebase was running two contradictory definitions of
"old-old" simultaneously: service-preference scoring used the real 70+
split, while movement probability and search weighting used the
elderly-headcount split.

## 12.4 The fix — `hh_age_group.m` is now the single source of truth

```matlab
g = hh_age_group(HH_data)        % one entry per household
g = hh_age_group(HH_data, rows)  % only the given row indices
% returns column vector: 0 = non-elderly, 1 = young-old, 2 = old-old
```

- Old-old takes priority: `>=1` member aged 70+ makes the whole household
  old-old; an elderly household with no 70+ member is young-old.
- Elderly membership still comes from `col5 >= 2` — **unchanged**, so
  elderly vs non-elderly totals are identical to before.
- Datasets with no col 12 (pre-age-split `.mat` files) degrade
  gracefully: every elderly household reports as young-old (group 1).

**Encoding change:** `Asset_Avail(:,2)` now carries `0/1/2` instead of
`0/3/6`. Anything reading that column must use the new codes.

**Never** write `HH_data(:,5)==3` or `==6` to mean an age band again.
`HH_data(:,5)>=2` for "is elderly" remains correct and is used throughout.

## 12.5 Files changed

| File | What changed |
|---|---|
| `hh_age_group.m` | **NEW.** The helper. Header documents both columns and the misclassification numbers. |
| `who_is_moving.m` | `young_old`/`old_old` (gating `eld_movef` / `eld_movef_old`) now from helper |
| `new_house.m` | `ageGroup>=1` for weighted pick; `==2` selects `oo_exponent` |
| `find_new_house_sa_score.m` | `isElderly`; `pick_weighted_sa`'s old-old test now `==2` |
| `find_new_house_same_stat.m` | `ageGroup`/`isElderly`; writes 0/1/2 into `Asset_Avail(:,2)` |
| `find_new_house_yeshuv.m` | same |
| `run_model_earthquake.m` | `diag_allpop_pre_group`, `young_old`/`old_old`, `Metric_Track` 24/25, `AA_YO`/`AA_OO` |
| `run_model_earthquake_floorspace.m` | same |
| `pref_hh.m`, `SA_score_old.m` | were already correct; repointed at the helper so the rule lives in one place |
| `nextchangesfortracker.m`, `nextchangesfortracker_shockpolicies.m` | `AA_E` test — see §12.7 |

`Metric_Track` column indices are UNCHANGED (24 = young-old count, 25 =
old-old count, plus 26-33 and 43-47 in the floorspace variant). All
`analysis_scripts/*.py` keep working untouched; they simply now receive
correct numbers.

## 12.6 What this means for runs and existing results

**Results will change.** Affected paths, in rough order of impact:

1. `who_is_moving.m` gates **whether elderly households move at all**. Any
   run with `eld_movef_old != eld_movef` now applies the old-old
   multiplier to 1701 households instead of 1019.
2. `elderly_search_mode` 3/4/5/6 and the `pick_weighted_sa` / `new_house`
   service weighting apply old-old-strength weighting to a different (and
   larger) set of households.
3. `Metric_Track` cols 24/25 and every age-split metric downstream of
   `Asset_Avail(:,2)`.

**Note on the finalized methodology (see QUICK REFERENCE at top):** plain
mode 2 with `svc_filter=1` and no `eld_movef` reaches `pref_hh` /
`SA_score_old`, which were already correct — but mode 2 also calls
`pick_weighted_sa`, which was not. So mode 2 results do change.

**Existing `earthquakeF/*.mat` outputs that split by age group are not
comparable to new runs.** Re-run before mixing old and new results in one
report. Runs reported only as elderly-vs-non-elderly aggregate are
unaffected (those totals did not change).

## 12.7 Second bug fixed in passing

`nextchangesfortracker.m` and `nextchangesfortracker_shockpolicies.m`
tested `AA_E = Asset_Avail(:,2)==1` for "elderly", but that column held
`0/3/6` — so `AA_E` matched **nothing**. Elderly possible-asset metrics
(`Metric_Track` cols 8 and 12) were silently always 0, and cols 10/14
always `NaN`, in both scripts. Now `>=1` under the 0/1/2 encoding, so they
populate. If you have old results from those two scripts showing zero
elderly asset availability, that was the cause — not a modelling result.

## 12.8 Verification performed

- `mlint` (MATLAB R2025b) on all 12 touched files: **zero syntax errors**.
- Helper run against `data_for_model_tmine_agesplit70.mat`:
  - non-elderly 13472 / young-old 2277 / old-old 1701
  - elderly total `sum(g>=1)` = 3978 = `sum(col5>=2)` — **unchanged**
  - `sum(g==2)` = 1701 = `sum(col12>=1)` — matches
  - scalar and row-subset call forms both correct
  - col-12-absent fallback: 0 old-old, 3978 elderly — graceful
- Not run: a full simulation. **No end-to-end run has been done since
  this change.** Do a short smoke run before committing to a long batch.

## 12.9 Where the Tiberias age-split dataset comes from

Asked in the same session, recorded here because it is not obvious:

- **Driver:** `data_allocation/run_regenerate_tveria_fix.m` produced the
  current `data_for_model_tmine_agesplit70.mat`. It mirrors
  `main_alloc.m`'s 5 stages with the corrected buildings CSV and
  `unit_size_scale=1.7806` (vacancy tuning).
- **Stages:** `start_spatial_dataupdate` -> `start_HH_2018up` ->
  `distribute_HH_2019` -> `create_work_place` -> `distribute_workers`.
- **Source data:** `modelthesis/TVR/` (`bldgs_height_tt.csv` — now the
  corrected 4165-building Tveria file; `model parameters.csv`).
- The `_agesplit70` suffix is **only a naming convention**. There is no
  separate age-split stage; `create_HH_12_2018.m` bakes the split in
  unconditionally. `main_alloc.m` runs the same pipeline under the name
  `data_for_model_tmine`.
- Two identical copies exist: `data_allocation/` and the `modelthesis/`
  root. Backups: `*_PRE_DENSITY_FIX_BACKUP.mat`,
  `*_PRE_TVERIA_CSV_FIX_BACKUP.mat`.
- 1.5x job-density variant: `run_regenerate_scaled_dataset.m` (reuses
  `data_after_lur.mat`, reruns only stages 4-5).

To regenerate, from `data_allocation/`: `matlab -batch "run_regenerate_tveria_fix"`

## 12.10 Open items from this section

1. **Nothing is committed.** The working tree already had substantial
   unrelated uncommitted work (deleted `earthquakeF/*.mat`, modified
   `TVR/bldgs_height_tt.csv`, `standard_report.py`, etc.), so staging was
   left to the user. `hh_age_group.m` is untracked — do not lose it.
2. **No end-to-end simulation run since the change.** Smoke-test first.
3. `is_old_old_lookup` (per-individual 70+ flag) is built by the
   allocation pipeline and saved, but no model code reads it. If you ever
   need within-household age resolution rather than household-level,
   that is where it is.
4. §11's worktree (`.claude/worktrees/elderly-search-methodology`) has its
   own copies of these files and **has NOT received this fix.** If that
   branch is ever merged, re-apply or re-verify there.
5. `modellab/` (sibling Ashkelon project) was explicitly out of scope and
   is untouched. It has the same `young_old`/`old_old` pattern in
   `run_model_earthquake_shelteroverflow.m` and would need the same fix if
   Ashkelon data ever gains a col 12.
