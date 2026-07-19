# Day → Week Step Rescaling Audit

`run_model_earthquake.m` and its called functions — Ashkelon ABM

We're considering changing the model so each step represents a week instead of a day. This identifies every place a probability, rate, or duration is currently calibrated assuming a daily step. **Nothing has been changed yet** — identification only.

## Findings

| # | Location | Constant / formula | Current (daily) | Fix |
|---|---|---|---|---|
| 1 | `migration_19.m:8` | `x = sas_data(i,5)/365` (inOutRatio) | annual rate → daily | `/52` instead of `/365` |
| 2 | `who_is_moving.m:7,12`, fed by `read_sas_data.m` | `intraSAProb`/`intraYeshuvProb` vs. per-step random draw | daily move probability | `p_week = 1-(1-p_day)^7` — confirm with data source first |
| 3 | `run_model_earthquake.m:137` | `subsidy_duration = 60` | ~2 months | ~9 |
| 4 | `run_model_earthquake.m:145` | `max_shelter_duration = 120` | ~4 months | ~17 |
| 5 | `run_model_earthquake.m:465-467` (+~705) | `VISITS` rolling window `>31` | ~1 month | ~4-5 |
| 6 | `run_model_earthquake.m:469` | `lu_warmup = 30` | ~1 month, coupled to #5 | ~4-5 |
| 7 | `run_model_earthquake.m:470` | `lu_update_every = 1` | "every step" — meaning shifts silently | explicit decision, not automatic |
| 8 | `run_model_earthquake.m:807` | `mod(i,30)==0` (SA/price update block) | ~1 month cadence | `mod(i,4)==0` |
| 9 | `find_job_1.m:44` | `T = 1-exp(-time/30)` | ~1 month, inside an exponential | ~4-5, verify curve shape numerically |
| 10 | `run_model_earthquake.m:128,342,346,348` | `RECOVERY = 0.01` per step | full recovery ≈100 days | ×7 → `0.07` |
| 11 | `run_model_earthquake.m:735-760` | `alfa/beta/lamda/delta` wage adjustment (`income_ratio`) | compounds every step | **no scalar fix — needs recalibration** |
| 12 | `run_model_earthquake.m:763-773` | Labor-force entry probability (driven by `income_ratio`) | downstream of #11 | re-tune together with #11 |
| 13 | `monthly_ass_cost.m` (called every step) | "monthly" cost-of-life recomputed every step | already mismatched today | no fix needed — weekly steps make this less wrong |

## Notes

- Items 1, 3–6, 8–10 are mechanical divide/multiply-by-7 rescales — low risk.
- Item 2 is mechanical but should be confirmed against the source spreadsheet (are those columns really daily?) before applying the conversion.
- Item 7 needs an explicit decision, not an automatic fix.
- Items 11–12 (wage adjustment) are the one place with real uncertainty — no formula swap will do it; needs empirical recalibration (e.g. compare `average_wage` trajectory over the same real 30 days, old vs. new step size).
- Item 13 requires no action.
