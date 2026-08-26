# Handover — Tiberias ABM thesis work (modelthesis/)

Written for a fresh Claude Code chat picking up this repo with no memory of
the prior conversation. Covers everything from git commit `f85975c` ("Fix
retry/migration/relocation bugs in earthquake model; add old-old
service-weight differentiation") through the current, **partially
uncommitted** working tree. Read this before touching any of the files
below.

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
