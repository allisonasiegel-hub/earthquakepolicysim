# CLAUDE.md — Ashkelon ABM Project (Allison Siegel, Hebrew University)

## Project Overview

MATLAB agent-based model (ABM) simulating urban housing dynamics and post-earthquake recovery in Ashkelon, Israel. The model has three sub-markets: housing, labor, and business. Current work focuses on a **baseline (no-shock) sensitivity testing** framework for three new parameters added for Allison's thesis.

---

## Tech Stack

- **Language:** MATLAB (script-based, not OOP)
- **Data:** `data_for_model_Ash2.mat` — Ashkelon spatial/household data
- **SAS data:** `sas_national.xlsx` — Israeli census intra-SA migration probabilities
- **Execution model:** `run('nextchangesfortracker.m')` — the script runs in the caller's workspace (critical: all `clearvars` calls also affect the caller)
- **No toolboxes required** beyond standard MATLAB

---

## Key Files

| File | Role |
|---|---|
| `nextchangesfortracker.m` | Main simulation script (reduced-runtime testing version). All metric tracking lives here. |
| `run_model_eq.m` | Untouched full-run version (more steps, land-use submodel active). Port changes here once parameters are finalized. |
| `run_sweep_setting.m` | Function wrapper that calls `nextchangesfortracker.m` once and returns results struct. Isolated function workspace protects against `clearvars`. Accepts `svc_filter` as 5th arg. |
| `run_sensitivity_sweep.m` | OAT sweep driver. Three axes: `wservice`, `eld_movef`, `svc_filter`. Outputs `.mat`, `.csv`, `.xlsx`. |
| `pref_hh.m` | Household preference score function. Elderly only: includes service preference weighted by `wservice`. Reads `stat_data(:,5)`. |
| `SA_score_old.m` | SA scoring for relocation decisions. Same elderly service preference logic as `pref_hh`. Reads `stat_data(:,5)`. |
| `who_is_moving.m` | Determines which households attempt to move. Uses `eld_movef` to scale elderly movement probability. |
| `find_new_house_same_stat.m` | Housing search for K=2 pathway (intra-SA + same-yeshuv). Applies `svc_filter` to within-SA pool for elderly. Populates 8-col `Asset_Avail`. |
| `find_new_house_yeshuv.m` | Housing search for K=3 pathway (inter-SA, same-yeshuv and other-yeshuv). Populates 8-col `Asset_Avail`. |
| `find_new_house_sa_score.m` | SA-score-ranked housing assignment. Bug-fixed: filters `possible_assets` to accepted SAs before calling `new_house`. Returns `n_accepted` (8th output). |
| `stat_service.m` | Called ONCE at init → `stat_data(:,2)` (static, commercial+public / residential). Never overwritten. |
| `ass_price.m` | Uses `stat_data(:,2)` for initial asset pricing. Called once at setup. |
| `building_service_ratio.m` | Computes per-building service ratio: commercial-only (usage 2–3) within 400m / residential. Stored in `Build_Data(:,19)`. |

---

## Data Structures

### `HH_data` (household matrix)
| Col | Meaning |
|---|---|
| 1 | SA (Statistical Area) ID |
| 2 | Household ID |
| 5 | Elderly count (≥2 = elderly household) |
| 6 | Income |
| 9 | Yeshuv (settlement) ID |
| 10 | Building ID |
| 11 | Asset ID |

### `Assets`
| Col | Meaning |
|---|---|
| 1 | SA ID |
| 2 | Building ID |
| 3 | Asset ID |
| 11 | Occupied (0=empty) |
| 12 | Price |
| 13 | Monthly cost |

Affordability thresholds:
- Same-SA pool: `Assets(:,13) <= 0.33 * income`
- Same-yeshuv (Y) and other-yeshuv (O) pools: `Assets(:,13) <= 1 * income`

### `Build_Data`
| Col | Meaning |
|---|---|
| 1 | Building ID |
| 3 | Usage type (1=residential, 2–3=commercial, 5=public) |
| 4 | SA ID |
| 19 | Building service ratio (commercial-only within 400m / residential) |

### `stat_data`
| Col | Meaning |
|---|---|
| 1 | SA ID |
| 2 | Static service ratio from `stat_service.m` — (commercial+public)/residential. Never overwritten. Used by `ass_price.m`. |
| 5 | Dynamic commercial-only service ratio — refreshed every 30 steps. Used by `pref_hh.m` and `SA_score_old.m`. |
| 6 | Baseline audit copy of col(5) — set once at init, never overwritten. |

**Formula for col(5) and col(6):** `commercial / residential` = `(usage 2–3) / (usage 1)` — commercial-only to match `building_service_ratio.m`. This is intentionally different from col(2) which includes public buildings (usage 5).

### `Asset_Avail` — reset each step, 8 columns
| Col | Meaning |
|---|---|
| 1 | HH_ID |
| 2 | isElderly (1/0) |
| 3 | n_SA — count of possible assets in same-SA pool (after svc_filter if applicable) |
| 4 | n_city — count of possible assets in accepted out-of-SA SAs (from `find_new_house_sa_score`) |
| 5 | tried_SA — 1 if HH attempted within-SA move this step |
| 6 | tried_city — 1 if HH attempted out-of-SA move this step |
| 7 | success_SA — 1 if successfully relocated within SA |
| 8 | success_city — 1 if successfully relocated out of SA |

**Note:** cols 5 and 6 can both be 1 for K=2 pathway HH (tries within-SA first, fails, then tries yeshuv/city).

### `Metric_Track` — `nan(steps, 23)`
| Col | Metric |
|---|---|
| 1 | Step index |
| 2 | Mean SA service ratio — elderly HH |
| 3 | Mean SA service ratio — non-elderly HH |
| 4 | Mean building service ratio — elderly HH |
| 5 | Mean building service ratio — non-elderly HH |
| 6 | Elderly population count |
| 7 | Non-elderly population count |
| 8 | Total possible assets (SA pool) — sum over moving elderly HH |
| 9 | Total possible assets (SA pool) — sum over moving non-elderly HH |
| 10 | Normalized possible assets (SA pool) — col8 / n moving elderly HH |
| 11 | Normalized possible assets (SA pool) — col9 / n moving non-elderly HH |
| 12 | Total possible assets (city pool) — sum over moving elderly HH |
| 13 | Total possible assets (city pool) — sum over moving non-elderly HH |
| 14 | Normalized possible assets (city pool) — col12 / n moving elderly HH |
| 15 | Normalized possible assets (city pool) — col13 / n moving non-elderly HH |
| 16 | Attempt rate within SA — elderly (per-SA attempts/HH, averaged across SAs) |
| 17 | Attempt rate within SA — non-elderly (same) |
| 18 | Attempt rate within city — elderly (city attempts / total elderly HH) |
| 19 | Attempt rate within city — non-elderly |
| 20 | Success rate within SA — elderly (successful SA relocations / SA attempts) |
| 21 | Success rate within SA — non-elderly |
| 22 | Success rate within city — elderly (successful city relocations / city attempts) |
| 23 | Success rate within city — non-elderly |

### `Metric_Change` — `nan(1, 18)` (final − initial for all)
| Index | Metric |
|---|---|
| 1 | SA service ratio delta — elderly |
| 2 | SA service ratio delta — non-elderly |
| 3 | Building service ratio delta — elderly |
| 4 | Building service ratio delta — non-elderly |
| 5 | Population delta — elderly |
| 6 | Population delta — non-elderly |
| 7 | Normalized possible assets SA delta — elderly |
| 8 | Normalized possible assets SA delta — non-elderly |
| 9 | Normalized possible assets city delta — elderly |
| 10 | Normalized possible assets city delta — non-elderly |
| 11 | Attempt rate SA delta — elderly |
| 12 | Attempt rate SA delta — non-elderly |
| 13 | Attempt rate city delta — elderly |
| 14 | Attempt rate city delta — non-elderly |
| 15 | Success rate SA delta — elderly |
| 16 | Success rate SA delta — non-elderly |
| 17 | Success rate city delta — elderly |
| 18 | Success rate city delta — non-elderly |

---

## New Parameters (Thesis Additions)

### `wservice` (default = 0)
Weight on service accessibility in elderly household preference score for **out-of-SA moves only**:
```matlab
Y = (income + age + wservice*service) / (2 + wservice);  % elderly only
Y = (income + age) / 2;  % non-elderly unchanged
```
- `service` = normalized dynamic SA service ratio: `(stat_data(:,5) - service_mean) / service_std`
- Applied in both `pref_hh.m` (HH threshold) and `SA_score_old.m` (destination SA score)
- Test grid: `[0, 0.25, 0.5, 1, 2]`
- Baseline (when sweeping other params): held at 0

### `eld_movef` (default = 1)
Multiplier on elderly household movement probability in `who_is_moving`:
```matlab
move_prob(elderly) = move_prob(elderly) * eld_movef;
```
- `1` = no change; `0` = elderly never move
- Values in (0,1) reduce elderly relocation rate
- Test grid: `[0, 0.25, 0.5, 0.75, 1]`
- `eld_movef=0` produces NaN for elderly metrics (expected — no attempts)

### `svc_filter` (default = 0)
Binary switch enabling building-level service ratio filter for **within-SA possible assets, elderly households only**:
```matlab
% in find_new_house_same_stat.m:
if isElderly && svc_filter==1
    % filter possible_assets to buildings where
    % Build_Data(:,19) >= current building's Build_Data(:,19)
end
```
- `0` = off (no filter); `1` = on (elderly within-SA pool filtered to buildings with service ratio ≥ current)
- Non-elderly are never affected regardless of setting
- Out-of-SA pools (yeshuv / other-yeshuv) are not filtered — SA-level service preference handled by `wservice`
- Test grid: `[0, 1]`

---

## Implemented Changes (This Session)

### 1. Bug fix: `find_new_house_sa_score.m`
`U_sa` (SAs passing the preference threshold) was computed but `possible_assets` was never filtered to those SAs before calling `new_house`. All assets in the original pool were being considered regardless of SA score.

**Fix:** Added `possible_assets_accepted = possible_assets(ismember(possible_assets(:,1), U_sa), :)` and pass that to `new_house`. Added `n_accepted` as 8th output.

### 2. Service ratio formula consistency
`stat_service.m` uses (commercial+public)/residential → stored in `stat_data(:,2)`. `building_service_ratio.m` uses commercial-only/residential → stored in `Build_Data(:,19)`.

**Decision:** Do not change either function. Instead, `stat_data(:,5)` (dynamic, used by `pref_hh` and `SA_score_old`) and `stat_data(:,6)` (baseline audit copy) now use commercial-only formula to match `building_service_ratio.m`. `stat_data(:,2)` preserved exactly as output by `stat_service.m`.

`service_mean` / `service_std` now computed from `stat_data(:,5)` (commercial-only), not col(2).

### 3. `Asset_Avail` redesigned — 4 cols → 8 cols
Old structure tracked total and same-SA asset counts. New structure tracks SA vs. city level separately with attempt and success flags. See data structure table above.

### 4. Metric_Track redesigned — 23 columns (fully replaced)
Removed: housing costs, displaced-HH metrics, old AAR/movement-rate columns.
Added: building service ratio averages per subgroup, raw + normalized possible assets at SA and city level, per-SA attempt rates, success rates at SA and city level.

### 5. Metric_Change redesigned — 22 values → 18 values
All deltas now reference new Metric_Track column indices.

### 6. `stat_data` col(5)/(6) formula updated in `nextchangesfortracker.m`
Init block and mod(30) update loop both changed from `(com+pub)/res` to `com/res`.

### 7. Sensitivity sweep expanded to three OAT axes
`run_sensitivity_sweep.m` fully rewritten. Added `svc_filter` axis `[0, 1]`. Output now includes `.mat`, `.csv`, and `.xlsx`. `results_long` table has 39 columns.

### 8. `run_sweep_setting.m` updated
Accepts `svc_filter` as 5th argument (default 0). Passes it into script workspace. Echoes it back in `res` struct.

### 9. `clearvars` keep-list updated
`svc_filter` added to the `-except` list so it survives script cleanup.

### 10. Bug fix: `locAA` zero-index crash in `nextchangesfortracker.m`
`ismember` on `Asset_Avail(:,1)` vs `HH_data(:,2)` could return 0 for unmatched rows → crash when indexing `HH_data`. Fixed with:
```matlab
valid_loc = locAA > 0;
AA_sa_id = zeros(size(Asset_Avail,1),1);
AA_sa_id(valid_loc) = HH_data(locAA(valid_loc), 1);
AA_sa_id(~valid_loc) = -1; % sentinel: won't match any real SA
```

---

## Architectural Decisions

### 1. `run()` + `clearvars` workspace isolation
`run()` executes in the caller's workspace. `nextchangesfortracker.m` ends with `clearvars -except [...]` which wipes the caller's workspace too. The keep-list includes: `wservice`, `eld_movef`, `svc_filter`, `steps`, `Metric_Track`, `Metric_Change`, `SA_Demographics`, and all core simulation outputs.

**Solution:** `run_sweep_setting.m` is a proper function (isolated scope). The `res` struct is built entirely **after** `run()` returns, using only variables known to survive `clearvars`.

### 2. `stat_data` column roles
- col(2): static (commercial+public)/residential from `stat_service.m`. Used only by `ass_price.m`. Never overwritten.
- col(5): dynamic commercial-only ratio. Refreshed every 30 steps. Used by `pref_hh.m`, `SA_score_old.m`.
- col(6): baseline audit copy of col(5). Set once at init, never overwritten.

### 3. Service filter scope
`svc_filter` applies **only** to the within-SA possible_assets pool in `find_new_house_same_stat.m`, and **only** for elderly households. Out-of-SA pools are unfiltered because SA-level service preference is handled through `wservice` in the preference/scoring functions.

### 4. Land-use submodel gate
Originally disabled with `if i > 99999`. Re-enabled:
```matlab
if ~exist('lu_warmup','var'); lu_warmup=30; end
if ~exist('lu_update_every','var'); lu_update_every=1; end
if i > lu_warmup && mod(i, lu_update_every) == 0
```
`lu_update_every=3` in sweep driver reduces runtime ~3x.

### 5. NaN in cost columns — carry-forward guard
`SA_POP_RATIO` divides by uninitialized zero-padded column → div/0 → NaN cascades through `B_VALUE` → `Assets(:,12)` → `Assets(:,13)`. Housing costs removed from metrics entirely, so this no longer affects `Metric_Track`.

### 6. `sims` variable set twice (intentional)
`sims=2` at top (sets outer `kk` loop bound). `sims=30` inside loop (no effect on outer loop). Outer loop runs 2 replicates; last kk's outputs are what `run_sweep_setting` captures.

### 7. Attempt rate within SA — per-SA denominator
Cols 16–17 of `Metric_Track` use a per-SA denominator (attempts in SA / HH of that subgroup in SA), then average across SAs. This avoids SAs with large populations dominating the metric.

---

## Sensitivity Sweep Framework

**Three OAT axes:**
- `wservice` sweep: `[0, 0.25, 0.5, 1, 2]` with `eld_movef=1`, `svc_filter=0`
- `eld_movef` sweep: `[0, 0.25, 0.5, 0.75, 1]` with `wservice=0`, `svc_filter=0`
- `svc_filter` sweep: `[0, 1]` with `wservice=0`, `eld_movef=1`

**Runtime settings:** `steps_sweep=90`, `lu_update_every=3`, `nReps=5`

**Output files:** `sensitivity_sweep_results.mat`, `sensitivity_sweep_results.csv`, `sensitivity_sweep_results.xlsx`

**Metrics in `results_long` (all split elderly/non-elderly):**
- Population delta
- SA service ratio average + delta
- Building service ratio average + delta
- Normalized possible assets SA: average + delta
- Normalized possible assets city: average + delta
- Attempt rate SA: average + delta
- Attempt rate city: average + delta
- Success rate SA: average + delta
- Success rate city: average + delta

---

## Spatial Hierarchy

```
Yeshuv (settlement)
  └── SA (Statistical Area) — finest census unit
        └── Buildings
              └── Assets (dwelling units)
```

Housing search order in `find_new_house_same_stat.m` (K=2 pathway):
1. Same SA, empty, `≤0.33*income` → [svc_filter applied for elderly] → assign via `new_house`
2. If step 1 fails: same yeshuv / other SA, empty, `≤1*income` → score-ranked via `find_new_house_sa_score`
3. If step 2 fails: other yeshuv, empty, `≤1*income` → score-ranked, flagged `new_a(:,2)=3`

`find_new_house_yeshuv.m` (K=3 pathway) skips step 1 entirely.

---

## Function Signatures & Logic — Housing Search Functions

### `find_new_house_sa_score.m`
```matlab
function [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change,n_accepted] = ...
    find_new_house_sa_score(pd,wservice,service_mean,service_std,stat_data, ...
    HH_data,Individuals_data,Build_Data,Build_Distance_matrix_400, ...
    Assets,wresd,FFF1,possible_assets)
```
- Called for all out-of-SA moves (yeshuv-pool and other-yeshuv-pool)
- `FFF1` = row index of the moving HH in `HH_data`
- `possible_assets` = pre-filtered asset rows passed in by caller
- Computes `pref` (HH threshold) via `pref_hh`, scores each unique SA in pool via `SA_score_old`
- **Bug fix:** filters `possible_assets` to `U_sa` (SAs where `score < pref`) before calling `new_house`
- `n_accepted` = number of assets in accepted SAs (0 if none pass threshold)
- Returns `new_a(:,2)=2` for same-yeshuv moves; caller sets `new_a(:,2)=3` for other-yeshuv

### `find_new_house_same_stat.m` (K=2 pathway)
```matlab
function [HH_ID,HH_data,Assets,HH_change,LU,new_A,new_B,Build_Data,Asset_Avail] = ...
    find_new_house_same_stat(HH_ID,pd,wservice,service_mean,service_std,stat_data, ...
    HH_data,Individuals_data,Build_Data,Build_Distance_matrix_400, ...
    Assets,wresd,FFF1,LU,new_A,new_B,HH_change,Asset_Avail,svc_filter)
```
- Loops over each HH in `FFF1`
- Builds three pools: `possible_assets` (same SA), `possible_assets_Y` (same yeshuv, other SA), `possible_assets_O` (other yeshuv)
- **If elderly and `svc_filter=1`:** filters `possible_assets` to buildings where `Build_Data(:,19) >= current building's Build_Data(:,19)`
- `n_SA = size(possible_assets, 1)` recorded **after** filter
- `tried_SA = 1` always (K=2 HH always has a within-SA attempt)
- `tried_city` starts at 0; flips to 1 if SA pool is empty and HH falls through to yeshuv pool, OR if SA attempt fails and `possible_assets_O` is tried
- `n_accepted_Y`, `n_accepted_O` captured from `find_new_house_sa_score` calls; summed into `n_city`
- `success_SA = 1` if `new_house` succeeds on within-SA pool; `success_city = 1` if any out-of-SA call succeeds
- Both `tried_SA` and `tried_city` can be 1 for the same HH in the same step
- `Asset_Avail` row appended: `[HH_ID, isElderly, n_SA, n_city, tried_SA, tried_city, success_SA, success_city]`

### `find_new_house_yeshuv.m` (K=3 pathway)
```matlab
function [HH_ID,HH_data,Assets,HH_change,LU,new_A,new_B,Build_Data,Asset_Avail] = ...
    find_new_house_yeshuv(HH_ID,pd,wservice,service_mean,service_std,stat_data, ...
    HH_data,Individuals_data,Build_Data,Build_Distance_matrix_400, ...
    Assets,wresd,FFF1,LU,new_A,new_B,HH_change,Asset_Avail)
```
- No `svc_filter` parameter — building service filter is never applied (no within-SA step)
- Builds two pools: `possible_assets_Y` (same yeshuv, other SA) and `possible_assets_O` (other yeshuv)
- `n_SA = 0`, `tried_SA = 0`, `success_SA = 0` always — K=3 HH never attempts within-SA move
- `tried_city = 1` always
- `n_accepted_Y`, `n_accepted_O` summed into `n_city`
- `success_city = 1` if either yeshuv call succeeds
- `Asset_Avail` row: `[HH_ID, isElderly, 0, n_city, 0, 1, 0, success_city]`

---

## Preference Score (`pref_hh.m`) and SA Score (`SA_score_old.m`)

These are called only for **out-of-SA moves** (yeshuv pool, other-yeshuv pool).

```matlab
% Elderly:
service = (stat_data(idx,5) - service_mean) / service_std;
Y = (income + age + wservice*service) / (2 + wservice);

% Non-elderly:
Y = (income + age) / 2;
```

`Y` from `pref_hh` = HH's preference threshold.
`score` from `SA_score_old` = destination SA's score.
Assignment condition: `score < pref` → SA is acceptable → assets in that SA are added to `possible_assets_accepted`.

---

## Outstanding Items

### High priority

1. **Port changes to `run_model_eq.m`:** All parameter additions (`wservice`, `eld_movef`, `svc_filter`, `lu_warmup`, `lu_update_every`, dynamic `stat_data` cols 5/6, full metric tracking redesign) need to be ported to the full-run version once parameter ranges are finalized.

2. **B_VALUE diagnostic `fprintf`:** Still present (around line 967–970). Remove or gate behind a `verbose` flag before final thesis runs.

3. **Root cause of B_VALUE NaN:** `SA_POP_RATIO` divides by uninitialized zero-padded column. Carry-forward guard was a mitigation. Housing costs removed from metrics so impact is reduced, but may still matter in `run_model_eq.m` (shock version).

### Lower priority / future

4. **Age sub-group split (65–74 vs. 75+):** Planned but not implemented. Waiting on statistical data. Currently elderly = `HH_data(:,5) >= 2`.

5. **Switch to Tiberias data:** Currently testing on Ashkelon (`data_for_model_Ash2`). Tiberias data not yet ready.

6. **`RelocationSummary` / `SA_Relocation`:** Computed at end of script but not used in sweep metrics. Will only be meaningful in full shock-run version (`shock_step=900`).

7. **`svc_filter` threshold:** Currently uses `>=` (destination building service ratio ≥ current). The threshold value (current building's ratio) is a design choice — could be a fixed percentile or parameter instead.
