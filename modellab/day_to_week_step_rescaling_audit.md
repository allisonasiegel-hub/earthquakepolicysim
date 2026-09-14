# Day → Week Step Rescaling Audit

Originally audited against `run_model_earthquake.m`. **Implemented** against
`run_model_earthquake_shelteroverflow.m` (the current main run script) - a
step there now represents a week, not a day. `migration_19.m` and
`find_job_1.m` are shared by both scripts, so rescaling them affects
`run_model_earthquake.m` too (deliberate - see decision log below).
`max_shelter_duration` (original item 4) no longer exists - that mechanism
was removed entirely in an earlier session. Two new day-calibrated
constants added since the original audit (`temp_dev_delay`,
`temp_dev_duration`, from the medium-term sheltering tier) are included
below since they didn't exist when this audit was first written.

## Findings

| # | Location | Constant / formula | Was (daily) | Now (weekly) | Status |
|---|---|---|---|---|---|
| 1 | `migration_19.m` | `x = sas_data(i,5)/365` (inOutRatio) | annual rate → daily | `/52` | **Done** |
| 2 | `read_sas_data.m` (feeds `who_is_moving.m` K=2/K=3) | `intraSAProb`/`intraYeshuvProb` vs. per-step random draw | daily move probability (confirmed for Ashkelon) | `p_week = 1-(1-p_day)^7`, applied at load time to cols 2-3 | **Done for Ashkelon; Tiberias needed a separate fix, see below** |
| 3 | `run_model_earthquake_shelteroverflow.m` | `subsidy_duration` | 60 (~2 months) | 9 | **Done** |
| 4 | ~~`max_shelter_duration`~~ | — | — | — | Removed (mechanism deleted, N/A) |
| 5 | `run_model_earthquake_shelteroverflow.m` (two occurrences) | `VISITS` rolling window `>31` | ~1 month | `>5` (4-step window + ID col) | **Done** |
| 6 | `run_model_earthquake_shelteroverflow.m` | `lu_warmup` | 30 (~1 month), coupled to #5 | 4 | **Done** |
| 7 | `run_model_earthquake_shelteroverflow.m` | `lu_update_every` | "every step" — meaning shifts silently | unchanged (=1) | Deferred - explicit decision, not automatic |
| 8 | `run_model_earthquake_shelteroverflow.m` | `mod(i,30)==0` (SA/price update block) | ~1 month cadence | `mod(i,4)==0` | **Done** |
| 9 | `find_job_1.m` | `T = 1-exp(-time/30)` | ~1 month, inside an exponential | `/(30/7)` ≈ 4.29 | **Done** — curve shape not separately re-verified numerically |
| 10 | `run_model_earthquake_shelteroverflow.m` | `RECOVERY = 0.01` per step | full recovery ≈100 days (deterministic, every building identical) | **Superseded** - mechanism replaced entirely with per-building weekly recovery probability calibrated from real data (31.35% of residential housing recovered within 1 year) - see decision log | **Done (superseded)** |
| 11 | `run_model_earthquake_shelteroverflow.m` | `alfa/beta/lamda/delta` wage adjustment (`income_ratio`) | compounds every step | unchanged | **Tested, accepted as-is** — see decision log |
| 12 | `run_model_earthquake_shelteroverflow.m` | Labor-force entry probability (driven by `income_ratio`) | downstream of #11 | unchanged | **Tested, accepted as-is** — see decision log |
| 13 | `monthly_ass_cost.m` (called every step) | "monthly" cost-of-life recomputed every step | already mismatched today | unchanged | No fix needed — weekly steps make this less wrong |
| 14 | `run_model_earthquake_shelteroverflow.m` | `temp_dev_delay` | 14 (2 weeks) | 2 | **Done** |
| 15 | `run_model_earthquake_shelteroverflow.m` | `temp_dev_duration` | 180 (~6 months) | 26 | **Done** |

## Decision log

- Items 1, 3, 5, 6, 8-10, 14-15 were mechanical divide/multiply-by-7
  rescales, applied directly.
- `migration_19.m`/`find_job_1.m` are shared with `run_model_earthquake.m`
  (not just the overflow script) - explicitly decided to rescale them
  anyway rather than fork per-script copies, since both scripts are
  intended to run on the same weekly step size going forward.
- Item 2: confirmed the source columns are daily probabilities, applied
  the conversion in `read_sas_data.m` (also shared with
  `run_model_earthquake.m` - same rescale-shared-functions decision as
  above). `interYeshuvProb` (col 4) is loaded but never actually used
  anywhere in the codebase, so left unconverted.
  - **Correction (Tiberias only, found later):** the "daily probability"
    confirmation above didn't hold for Tiberias's raw data - its median
    `intraSAProb` (0.0256) is ~1000x larger than Ashkelon's (0.0000336),
    the same "dimensionless ratio misused as an annual rate" pattern
    already found and fixed for `inOutRatio` in this same file (see
    `migration_19.m`). Confirmed via profiling: Tiberias was running
    11.7x slower than Ashkelon per step despite having fewer households
    (18k vs 36k) - `find_new_house_yeshuv`/`SA_score_old` were being
    called ~5,755 times/step because ~10-48% of the population was
    attempting a move every single week under the daily-rate
    interpretation. Reinterpreting Tiberias's raw values as ANNUAL
    rates (`p_week = 1-(1-p_annual)^(7/365)`, applied Tiberias-only in
    `run_model_earthquake_shelteroverflow.m` right after the
    `read_sas_data` call) brings them to within ~2-5x of Ashkelon's
    scale and empirically fixed both the runaway movement behavior and
    the performance (now faster than Ashkelon, as expected for a
    smaller population). Ashkelon's own values were left untouched -
    the original daily-probability conversion still holds for that
    city's data.
- Item 7 (`lu_update_every`) is a policy choice about update cadence, not
  a mechanical unit conversion - left as-is pending an explicit decision.
- Items 11-12 (wage adjustment): empirically tested rather than
  analytically fixed, since `income_ratio` compounds every step and
  there's no scalar conversion for that. Ran Ashkelon, no shock, 90 real
  days, 4 replicates each of a daily-step config (reverted temporarily via
  `git stash` to the pre-rescale state) and the current weekly-step config
  (13 steps), comparing `average_wage` trajectories (`sumdata.avgWage`,
  now kept through `clearvars` - see the keep-list) at matched real-time
  checkpoints:
    - Both start identical (8,897.66 - same initial data).
    - Weeks 1-2: large divergence (~7.6%) - the daily config's initial
      wage-settling transient completes within ~2-3 real days, while the
      weekly config takes ~2-3 real *weeks* for the same number of
      `income_ratio` applications, since that adjustment only fires once
      per step regardless of how much real time the step represents.
    - Week 3 onward: divergence drops to ~0.3-1.1% and stays roughly flat
      through day 90 - no runaway drift. Replicate-to-replicate noise
      alone is ~0.1-0.3%, so this residual gap is real but small.
  Decision: accepted as-is, not recalibrated. The long-run wage level
  isn't meaningfully distorted by the switch; only the speed of the
  initial post-shock adjustment is slower in calendar time. Revisit if a
  specific run cares about short-term (first few weeks) dynamics.
- Item 13 requires no action.
- Item 10 (RECOVERY) was later superseded: the deterministic shared-
  countdown mechanism (every destroyed building recovers at the exact
  same step count, since size cancels out of the threshold formula) can't
  represent a real recovery-rate statistic at all, since it produces a
  step function (0% recovered, then 100% all at once) rather than a
  curve. Replaced with a per-building weekly Bernoulli recovery draw,
  calibrated from real data (31.35% of residential housing recovered
  within 1 year): `RECOVERY = 1-(1-0.3135)^(1/52) ≈ 0.00721`. Applied
  uniformly to all building types (explicit decision, not residential-
  only) via the existing `priority_recovery`/`recovery_factor` toggle
  path, which still works for future differentiated-recovery scenarios
  but is inactive by default. `destroyed_B(:,2)` (the old progress
  accumulator) is now unused/vestigial - left in place since
  `destroyed_B(:,3)` (size) is still read elsewhere (e.g.
  `site_temp_dev_locations.m`) and removing a column would ripple through
  every caller unnecessarily.
