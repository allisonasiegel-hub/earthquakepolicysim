# Data Allocation: Validation Tools & Jerusalem Fix History

This document covers two things:
1. How to validate a city's synthetic population output against census data using `validate_allocation.py` / `plot_allocation.py`.
2. The census data correction and code bugs found and fixed while bringing Jerusalem (`JER`) up to a clean validation state.

---

## 1. Validating synthetic population data

The data-allocation pipeline (`main_alloc.m` → `start_spatial_dataupdate` → `start_HH_2018up` → `distribute_HH_2019` → `create_work_place` → `distribute_workers`) produces a cross-sectional synthetic population (`data_for_model_<CITY>.mat`) from census inputs (`<CITY>/sa_data_b7.csv`). `validate_allocation.py` and `plot_allocation.py` check that output against the census it was built from.

These tools are **city-agnostic**: pass `--city <NAME>` (matching the city folder name used in `main_alloc.m`'s `file`/`NAME` variables, e.g. `JER`, `TVR`, `BS08`, `Arad`, `ASH22`) and they derive the right paths automatically:
- `--mat` defaults to `data_allocation/data_for_model_<city>.mat`
- `--census` defaults to `<city>/sa_data_b7.csv`
- `--out` defaults to `data_allocation/allocation_validation_report_<city>.csv` (or `plots_allocation_<city>/` for the plotting script)

Any of these can still be overridden individually if you need a one-off path.

### Running the validator

```bash
python validate_allocation.py --city JER
```

This prints a report grouped into five categories and writes the same data to a CSV:

- **structural** — internal consistency checks that don't need census data at all: duplicate HH/individual IDs, orphaned records, assets double-assigned, workers with no workplace, negative prices, over-capacity workplaces. These should always read 0/OK; a non-zero value points to an allocation-stage bug, not a census mismatch.
- **demographics** — age-group shares (kid/adult/elderly), young-old/old-old split (if present), household size distribution, households with children/elderly, disability rates — each compared against the matching census column(s).
- **income** — individual income decile shares (compared to census `income.q1`-`q10`) and `HH_asiron` distribution (reported for visibility only — it's not directly census-comparable, since it re-buckets summed multi-earner household income through a per-person bracket table).
- **cars** — households with ≥1 / ≥2 vehicles.
- **labor** — labor force participation rate, employment rate, and commuting shares (outside-locality vs within-locality), plus counts of workers with no workplace and individuals who wanted work but didn't get any.

Each row is flagged `OK`, `FAIL`, or `INFO` (checks with no meaningful census comparison, e.g. `HH_asiron`, or “individuals wanting work but unemployed”, which the census can't validate directly). The FAIL threshold is 8 percentage points for share/percentage metrics, or 30% relative for count/rate metrics — see `PP_TOL` / `REL_TOL` in `validate_allocation.py`.

### Running the plots

```bash
python plot_allocation.py --city JER
```

Produces the same comparisons as bar charts (demographics, disabilities, income/cars, labor) plus SA-level choropleth maps of elderly household distribution, saved as PNGs and a combined `allocation_plots.pdf` under `plots_allocation_<city>/`. The elderly maps need a shapefile (`--shape`, only built so far for Tiberias at `../tveriashape/`); if the default path doesn't exist for the chosen city, that one panel is skipped with a message instead of erroring.

### Interpreting FAILs

A FAIL means the simulated output diverges from the census by more than tolerance — it does **not** by itself tell you whether the bug is in the allocation code or in the census input. Both turned out to be true for Jerusalem (see below). Useful diagnostic moves, in rough order of how cheap they are:
1. Check whether the *aggregate* household-level version of the metric agrees (e.g. "HH with children share") even when the *population*-level version doesn't (e.g. "kid share") — a mismatch between the two usually means population is inflated/deflated relative to what the household count implies, rather than the underlying household-composition target being wrong.
2. Check whether the census input's own percentage columns for that metric sum to what they should (e.g. a set of mutually-exclusive size/count buckets should sum to ~100%).
3. Check for duplicate values across supposedly-independent columns in the census row — a strong signal of an upstream extraction/join bug rather than random noise.

---

## 2. Jerusalem (`JER`) fix history

Validating `JER` against `JER/sa_data_b7.csv` started at **12 FAILs**. Fixing it took five separate changes, four in code and one in the census data itself, bringing it down to **0 FAILs**.

| Stage | FAILs remaining |
|---|---|
| Original | 12 |
| + household-size normalization (later superseded) | 9 |
| + elderly-count fix | 8 |
| + labor-block fixes | 4 |
| + corrected census data | **0** |

### 2.1 Elderly households wildly over-assigned
**File:** `create_HH_12_2018.m`
A block partway through the function recomputed the target elderly count from `total_65` (`demog_yishuv.age_65_up`, a raw population *headcount*) via `round(sa_data(i,total_65)/100*sum(stat_HH(:,3)))` — dividing a headcount by 100 and multiplying by the SA's population inflated it roughly 10x. This was then clamped down by a downstream eligibility cap to "every eligible household," badly over-assigning elderly status.
**Fix:** the earlier, correctly-scaled household-based estimate (from `households.hh65_pcnt`) was renamed `num_65_target` and reused consistently instead of being recomputed from the population count later in the function.

### 2.2 Metro-zone commuting shares never derived, left NaN
**File:** `start_HH_2018up.m`
Jerusalem's census extract has `comm31`/`comm34` completely empty (NaN) for every SA — only `comm99` (share commuting outside the locality) is populated. The generic column-mean NaN-fill can't help an all-NaN column (mean of all-NaN is NaN).
**Fix:** added a derivation block: `comm31 = 1 - comm99` (its complement) and `comm34 = 0` (no data available for that metro zone), applied wherever the value is still NaN after the generic fill.

### 2.3 NaN commuting targets silently consumed the entire worker pool
**File:** `distribute_workers.m`
Before 2.2 was fixed, `worker_Metro_zone(j) = min(worker_Metro_zone(j), length(F))` — MATLAB's `min` ignores NaN and returns the other operand, so a NaN commuting target silently became "the entire remaining worker pool" instead of 0. Every worker got assigned a local workplace, and the "outside-locality" sentinel step downstream never ran (0% outside-locality / 100% within-locality, vs a ~13%/87% census split). A second, independent bug in the fallback assignment branch could also request more workplace assignments than remained in the worker pool, risking an out-of-bounds error.
**Fix:** added `worker_Metro_zone(isnan(worker_Metro_zone))=0` as a defensive fallback (belt-and-suspenders alongside 2.2), a `worker_Metro_zone(j)>0` guard on the fallback branch, and capped `num_assign` at `min(length(B),length(F))`.

### 2.4 Labor force inflated by sampling from the wrong pool
**File:** `labor_datasample.m`
`work=datasample(labor_force,...)` sampled the "currently working" flag from the *entire* labor-eligible population, instead of restricting to the `want_work` subset it was meant to upgrade. Since `work` and `want_work` were independent random samples of the same pool, their union (the effective labor force) came out larger than the census-targeted participation rate (simulated 81.7% vs census 62.2%).
**Fix:** changed the sampling pool from `labor_force` to `want_work`, so "working" status is only assigned within people who already want work.

### 2.5 Corrupted household-size percentages in the census input
**File:** `JER/sa_data_b7.csv` (data, not code)
The `households.size1_pcnt` through `size7up_pcnt` columns summed to a mean of **144%** across Jerusalem's SAs (range 70-288%, vs ~100% for every other city's file), and many rows had **exact duplicate values across buckets** (e.g. `size1_pcnt == size2_pcnt` in 58 of 113 rows) — the signature of an upstream extraction/join bug, not noise. This was the root cause of the household-size distribution, kid-share, and adult-share FAILs that survived all four code fixes above; the allocation code was working correctly, its input just wasn't.

**Interim workaround (since removed):** `create_HH_12_2018.m` normalized the 7 size-bucket percentages to sum to 1 before scaling to a household count. Without this, the assignment loop (which fills household-size buckets in order 1→7+) would target more households than actually existed whenever the input summed over 100%; MATLAB silently auto-grows the array past its real length in that case, and those overflow rows get deleted later — hitting whichever buckets are filled *last* (the larger sizes) hardest. Normalizing fixed the severe size-4/5/6/7+ undercount, but — because it rescales every bucket uniformly regardless of which ones are actually corrupted — it introduced a smaller new skew in sizes 1/2.

**Actual fix:** a second, independently-provided source file, `sa_data_jr.csv` (194 statistical areas, raw untransformed CBS export), was confirmed to be clean — its `size1_pcnt`...`size7up_pcnt` sum to ~100% (mean 99.99%), and cross-checking overlapping rows against the corrupted file showed identical values wherever the old file *wasn't* corrupted (e.g. `households.size_avg` and the `hh0_17_*` child-count buckets matched exactly), confirming both files share the same underlying source — only the size buckets in the old extract were broken.

`sa_data_b7.csv`'s 7 size-bucket columns were patched in place using `sa_data_jr.csv`:
- **100 SAs**: replaced directly, matched by statistical area ID.
- **8 SAs** present in the simulation but missing from the new file (`30000811, 30001021, 30001023, 30001024, 30001026, 30001114, 30001151, 30001817`): replaced using a manually-specified donor SA (a neighboring/comparable SA that *is* present in the new file).
- **5 SAs** not used by the simulation (no building data) and not covered by the new file: left untouched — harmless, since they're never read.

The original file is preserved at `JER/sa_data_b7_ORIGINAL_BACKUP.csv`. With clean input, the interim normalization workaround (2.5, code side) was removed from `create_HH_12_2018.m`, restoring it to the same logic used for every other city.

### Applying this elsewhere

If another city's validation run shows FAILs in the household-size/kid-share/adult-share cluster, check the census file's `size1_pcnt`...`size7up_pcnt` sum-to-100 first (see "Interpreting FAILs" above) before assuming a code bug — this exact failure mode is caused by bad input, not bad code, and no amount of downstream code changes fully substitutes for a clean source file. The elderly-count, commuting-share, and labor-force bugs (2.1-2.4), by contrast, were genuine code bugs independent of Jerusalem's specific data and are now fixed for every city using this pipeline.
