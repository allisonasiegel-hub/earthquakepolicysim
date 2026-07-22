# Sensitivity Sweep — Statistical Results Handoff

**Purpose of this document:** statistical results of a parameter sensitivity analysis of RABM
simulation outputs, prepared for interpretation in a separate context that knows the model
internals (variable definitions and how parameters enter the code). This document reports
*what was computed and what the numbers are* — no substantive interpretation is included.

---

## 1. Input data

File: `sensitivity_sweep_results.csv` (run-level, unsummarized).
60 rows = 12 parameter combinations x 5 replicates each.

- Design: one-at-a-time (OAT) sweep of 3 parameters. Column `ParamVaried` labels which
  parameter each row's sweep belongs to; `Replicate` (1-5) indexes runs.
- Parameters and levels swept:
  - `eld_movef`: 0, 0.25, 0.5, 0.75, 1.0 (with wservice=0, svc_filter=0)
  - `wservice`: 0, 0.25, 0.5, 1.0, 2.0 (with eld_movef=1.0, svc_filter=0)
  - `svc_filter`: 0, 1 (with wservice=0, eld_movef=1.0)
- 34 outcome columns: 17 outcome families x 2 population suffixes
  (`_E` = elderly, `_NE` = non-elderly). Families: PopChange, SAServiceAvg, SAServiceDelta,
  BldServiceAvg, BldServiceDelta, NormAssetsCity_Avg, NormAssetsCity_Delta, NormAssetsSA_Avg,
  NormAssetsSA_Delta, AttemptSA_Avg, AttemptSA_Delta, AttemptCity_Avg, AttemptCity_Delta,
  SuccessSA_Avg, SuccessSA_Delta, SuccessCity_Avg, SuccessCity_Delta.

### Missing data
Some outcomes contain NaN replicates (dropped per-test; `n_scen`/`n_ref` columns record the
n actually used). NaN counts (of 60 rows):

- NormAssetsSA_Delta_E: 57
- SuccessSA_Delta_E: 57
- SuccessCity_Delta_E: 37
- NormAssetsCity_Delta_E: 37
- SuccessSA_Delta_NE: 23
- NormAssetsSA_Delta_NE: 23
- NormAssetsCity_Delta_NE: 2
- SuccessCity_Delta_NE: 2
- AttemptCity_Delta_NE: 1
- AttemptCity_Delta_E: 1
- AttemptSA_Delta_NE: 1
- AttemptSA_Delta_E: 1

---

## 2. Methods

**Reference combination.** The three sweeps share the anchor point
`wservice=0, eld_movef=1.0, svc_filter=0`, which appears once in each sweep
(3 x 5 = 15 replicates). These 15 runs were pooled as the common reference group.
Every other combination (9 combos x 5 replicates) was tested against this pooled reference.

**Tests performed, per (combination, outcome) pair — 272 valid tests total:**

1. **Welch two-sample t-test** (unequal variances, two-sided) on the raw replicate values:
   scenario replicates (n = 5, sometimes 4 after NaN removal) vs pooled reference
   replicates (n = 15). Reported: `t_stat`, `p_value`.
2. **Cohen's d** (pooled-SD standardized mean difference): (mean_scen - mean_ref) / pooled SD.
   Sign convention: positive = scenario mean higher than reference mean.
3. **Percent change**: 100 x (mean_scen - mean_ref) / |mean_ref|.
4. **Benjamini-Hochberg FDR correction** applied across all 272 p-values, reported as
   `q_value`. Threshold used for the "significant" table below: q < 0.05.

**Statistical power caveat:** with n=5 vs n=15, only effects of roughly |d| >= 1.5-2 can
reach q < 0.05. Absence from the significant table does not imply absence of effect.

**Outlier screening:** per (combination, outcome), modified z-score = 0.6745 x (x - median)/MAD,
flag threshold |z| > 3.5. NOTE: with n=5 this method over-flags severely when replicate values
are nearly identical (MAD near 0 inflates z; flags with |z| > 50 on near-zero Delta outcomes are
artifacts of this, not genuine anomalies). 88 raw flags were produced; treat only replicates
flagged consistently across many outcomes as potentially suspicious.

Replicates flagged on >= 4 outcomes (combo format: ParamVaried wservice eld_movef svc_filter):

- eld_movef 0.0 0.75 0 | replicate 2: flagged on 8 outcomes
- wservice 0.0 1.0 0 | replicate 5: flagged on 4 outcomes
- eld_movef 0.0 0.0 0 | replicate 5: flagged on 4 outcomes
- wservice 0.5 1.0 0 | replicate 5: flagged on 4 outcomes

---

## 3. Results

### 3.1 Effects significant after FDR correction (q < 0.05) — 20 of 272 tests

Sorted by |Cohen's d| descending. `mean` = scenario mean, `ref_mean` = pooled reference mean.

| combo | outcome | mean | ref_mean | pct_change | cohens_d | p_value | q_value | n_scen | n_ref |
|---|---|---|---|---|---|---|---|---|---|
| wservice=1 | AttemptSA_Avg_E | 0.00244 | 0.0022 | 10.82838 | 5.5661 | 0.0 | 0.0 | 5 | 15 |
| wservice=0.25 | AttemptSA_Avg_E | 0.00243 | 0.0022 | 10.12363 | 4.79081 | 1e-05 | 0.00051 | 5 | 15 |
| wservice=2 | AttemptSA_Avg_E | 0.00243 | 0.0022 | 10.56182 | 4.66335 | 0.00018 | 0.00447 | 5 | 15 |
| wservice=1 | SAServiceAvg_E | 2.42886 | 2.38688 | 1.75876 | 4.48792 | 1e-05 | 0.00037 | 5 | 15 |
| svc_filter=1 | AttemptCity_Avg_E | 0.00195 | 0.00169 | 15.26866 | 4.43736 | 0.0 | 3e-05 | 5 | 15 |
| wservice=2 | SAServiceAvg_E | 2.43011 | 2.38688 | 1.81143 | 4.41363 | 8e-05 | 0.00229 | 5 | 15 |
| wservice=0.5 | SAServiceAvg_E | 2.42437 | 2.38688 | 1.57097 | 4.19011 | 0.0 | 1e-05 | 5 | 15 |
| wservice=0.5 | AttemptSA_Avg_E | 0.00241 | 0.0022 | 9.51649 | 4.13524 | 0.00047 | 0.01074 | 5 | 15 |
| wservice=0.25 | SAServiceAvg_E | 2.42321 | 2.38688 | 1.52222 | 3.85481 | 4e-05 | 0.00116 | 5 | 15 |
| eld_movef=0 | AttemptCity_Avg_E | 0.00146 | 0.00169 | -13.58895 | -3.45018 | 0.00123 | 0.0197 | 5 | 15 |
| eld_movef=0.25 | PopChange_E | -58.0 | -95.6 | 39.33054 | 3.4359 | 3e-05 | 0.0011 | 5 | 15 |
| eld_movef=0 | PopChange_E | -56.6 | -95.6 | 40.79498 | 3.1548 | 0.0022 | 0.03328 | 5 | 15 |
| eld_movef=0.25 | AttemptCity_Avg_E | 0.0015 | 0.00169 | -10.87434 | -2.95053 | 0.00072 | 0.01498 | 5 | 15 |
| eld_movef=0.5 | AttemptCity_Avg_E | 0.00152 | 0.00169 | -9.92549 | -2.92465 | 0.0 | 0.00025 | 5 | 15 |
| wservice=1 | PopChange_E | -64.8 | -95.6 | 32.21757 | 2.58246 | 0.00348 | 0.04782 | 5 | 15 |
| wservice=1 | SAServiceDelta_E | 0.9299 | 0.86737 | 7.20884 | 2.06866 | 0.00088 | 0.01608 | 5 | 15 |
| svc_filter=1 | SuccessSA_Avg_E | 0.26604 | 0.32691 | -18.61882 | -1.95209 | 1e-05 | 0.00037 | 5 | 15 |
| wservice=0.25 | SAServiceDelta_E | 0.92305 | 0.86737 | 6.41855 | 1.8667 | 0.00089 | 0.01608 | 5 | 15 |
| wservice=0.5 | SAServiceDelta_E | 0.92251 | 0.86737 | 6.35606 | 1.8466 | 0.00102 | 0.01734 | 5 | 15 |
| eld_movef=0 | AttemptSA_Delta_NE | -0.0 | -3e-05 | 90.8122 | 1.02563 | 0.00352 | 0.04782 | 4 | 15 |

### 3.2 Moderate-to-large effects NOT significant after correction (|d| >= 0.8, q >= 0.05) — 40 tests

Candidates for follow-up with more replicates; at n=5 these are underpowered, not disproven.

| combo | outcome | pct_change | cohens_d | p_value | q_value | n_scen |
|---|---|---|---|---|---|---|
| wservice=2 | NormAssetsCity_Avg_E | 32.9615 | 2.6789 | 0.0132 | 0.1312 | 5 |
| eld_movef=0 | NormAssetsCity_Avg_E | -27.3528 | -2.4185 | 0.0123 | 0.1282 | 5 |
| wservice=2 | SAServiceDelta_E | 7.6692 | 2.0829 | 0.005 | 0.0616 | 5 |
| wservice=0.5 | PopChange_E | 26.569 | 1.9962 | 0.0211 | 0.1742 | 5 |
| eld_movef=0.25 | NormAssetsCity_Avg_NE | -5.9058 | -1.9542 | 0.0097 | 0.1054 | 5 |
| wservice=0.5 | NormAssetsCity_Avg_E | 19.8581 | 1.8691 | 0.0208 | 0.1742 | 5 |
| svc_filter=1 | PopChange_E | -19.6653 | -1.6507 | 0.0135 | 0.1312 | 5 |
| eld_movef=0.5 | PopChange_E | 21.9665 | 1.5923 | 0.0561 | 0.3632 | 5 |
| wservice=0.25 | PopChange_E | 20.5021 | 1.5864 | 0.0393 | 0.2767 | 5 |
| svc_filter=1 | NormAssetsSA_Avg_E | -39.8197 | -1.5504 | 0.0041 | 0.0533 | 5 |
| eld_movef=0.25 | SuccessCity_Avg_NE | -2.6109 | -1.5253 | 0.0347 | 0.2633 | 5 |
| wservice=1 | NormAssetsCity_Avg_E | 16.8792 | 1.4796 | 0.0702 | 0.415 | 5 |
| wservice=2 | PopChange_E | 16.318 | 1.3591 | 0.0342 | 0.2633 | 5 |
| svc_filter=1 | AttemptCity_Avg_NE | -2.0621 | -1.2329 | 0.0348 | 0.2633 | 5 |
| eld_movef=0.75 | AttemptCity_Avg_E | -4.2154 | -1.2164 | 0.0163 | 0.1475 | 5 |
| wservice=0.5 | AttemptCity_Avg_NE | -1.8617 | -1.1664 | 0.0155 | 0.1456 | 5 |
| svc_filter=1 | AttemptSA_Avg_E | 3.8445 | 1.1468 | 0.2182 | 0.8019 | 5 |
| eld_movef=0.75 | NormAssetsCity_Delta_NE | -39.846 | -1.143 | 0.0067 | 0.0756 | 5 |
| eld_movef=0 | SuccessCity_Avg_E | -9.7423 | -1.1373 | 0.1109 | 0.5912 | 5 |
| eld_movef=0 | SuccessCity_Avg_NE | 1.7795 | 1.1263 | 0.0397 | 0.2767 | 5 |
| eld_movef=0.5 | AttemptCity_Delta_E | 1062.5541 | 1.0979 | 0.2169 | 0.8019 | 5 |
| wservice=0.5 | SuccessCity_Delta_E | 54.2857 | 1.0937 | 0.1339 | 0.6555 | 5 |
| eld_movef=0 | PopChange_NE | 11.344 | 1.0884 | 0.0902 | 0.5005 | 5 |
| svc_filter=1 | NormAssetsCity_Delta_NE | -45.4834 | -1.0868 | 0.1277 | 0.6487 | 5 |
| wservice=0.5 | PopChange_NE | 11.056 | 1.0464 | 0.1098 | 0.5912 | 5 |
| eld_movef=0.25 | SuccessSA_Avg_NE | -8.2865 | -1.0264 | 0.1915 | 0.8019 | 5 |
| svc_filter=1 | SuccessCity_Delta_E | 42.8571 | 1.0113 | 0.1742 | 0.7896 | 4 |
| eld_movef=0.75 | NormAssetsSA_Avg_E | 30.9637 | 0.9818 | 0.1898 | 0.8019 | 5 |
| wservice=1 | AttemptSA_Delta_NE | 84.3409 | 0.9771 | 0.006 | 0.0704 | 5 |
| eld_movef=0.5 | BldServiceDelta_E | 1.5815 | 0.9727 | 0.0622 | 0.3843 | 5 |
| wservice=0.5 | NormAssetsSA_Avg_NE | 15.6034 | 0.9109 | 0.0679 | 0.4106 | 5 |
| eld_movef=0.5 | BldServiceAvg_E | 1.132 | 0.9098 | 0.0429 | 0.2875 | 5 |
| wservice=0.5 | AttemptCity_Delta_E | 813.862 | 0.9072 | 0.2731 | 0.906 | 5 |
| wservice=0.25 | NormAssetsCity_Avg_E | 8.9538 | 0.9062 | 0.1198 | 0.6268 | 5 |
| wservice=1 | AttemptCity_Avg_E | -2.968 | -0.8777 | 0.0366 | 0.2692 | 5 |
| eld_movef=0.75 | SuccessCity_Avg_NE | 1.2756 | 0.8662 | 0.0183 | 0.1607 | 5 |
| eld_movef=0.25 | NormAssetsCity_Delta_NE | 36.5873 | 0.857 | 0.224 | 0.8019 | 5 |
| eld_movef=0 | SuccessCity_Delta_NE | 25.6798 | 0.8569 | 0.3831 | 0.9682 | 4 |
| eld_movef=0.25 | PopChange_NE | 9.424 | 0.8503 | 0.2139 | 0.8019 | 5 |
| eld_movef=0.75 | NormAssetsSA_Delta_NE | -181.9869 | -0.8401 | 0.5107 | 0.9934 | 3 |

### 3.3 Combination ranking (aggregated over all outcomes)

`median_abs_d` = median |Cohen's d| across that combination's outcomes;
`n_significant` = outcomes with uncorrected p < 0.05; `max_abs_d` = strongest single effect.

| combo | median_abs_d | n_significant | n_outcomes | max_abs_d | max_effect_outcome |
|---|---|---|---|---|---|
| wservice=0.5 | 0.466 | 6 | 32 | 4.19 | SAServiceAvg_E |
| svc_filter=1 | 0.42 | 5 | 32 | 4.437 | AttemptCity_Avg_E |
| eld_movef=0 | 0.396 | 5 | 28 | 3.45 | AttemptCity_Avg_E |
| eld_movef=0.75 | 0.371 | 3 | 32 | 1.216 | AttemptCity_Avg_E |
| eld_movef=0.25 | 0.345 | 4 | 30 | 3.436 | PopChange_E |
| wservice=1 | 0.284 | 7 | 30 | 5.566 | AttemptSA_Avg_E |
| eld_movef=0.5 | 0.278 | 2 | 28 | 2.925 | AttemptCity_Avg_E |
| wservice=2 | 0.231 | 5 | 30 | 4.663 | AttemptSA_Avg_E |
| wservice=0.25 | 0.218 | 4 | 30 | 4.791 | AttemptSA_Avg_E |

### 3.4 Parameter ranking (aggregated over combos and outcomes)

| param_varied | median_abs_d | max_abs_d | pct_significant |
|---|---|---|---|
| svc_filter | 0.42 | 4.437 | 15.625 |
| wservice | 0.367 | 5.566 | 18.033 |
| eld_movef | 0.345 | 3.45 | 11.864 |

### 3.5 Dose-response means (mean per level, sd in parentheses; selected outcomes)

- **PopChange_E** across eld_movef: eld_movef=0: -56.6 (sd 15), eld_movef=0.25: -58 (sd 8.8), eld_movef=0.5: -74.6 (sd 17.9), eld_movef=0.75: -88.6 (sd 5.41), eld_movef=1: -88.8 (sd 4.38)
- **PopChange_NE** across eld_movef: eld_movef=0: -369.4 (sd 46.9), eld_movef=0.25: -377.4 (sd 57.5), eld_movef=0.5: -411.6 (sd 14.7), eld_movef=0.75: -412.8 (sd 50.6), eld_movef=1: -398 (sd 55.6)
- **AttemptSA_Avg_E** across eld_movef: eld_movef=0: 0.0022267 (sd 7.84e-05), eld_movef=0.25: 0.0022065 (sd 5.74e-05), eld_movef=0.5: 0.0021818 (sd 4.28e-05), eld_movef=0.75: 0.0021873 (sd 2.3e-05), eld_movef=1: 0.0022135 (sd 3.68e-05)
- **SAServiceAvg_E** across eld_movef: eld_movef=0: 2.387 (sd 0.0153), eld_movef=0.25: 2.3867 (sd 0.014), eld_movef=0.5: 2.3882 (sd 0.00821), eld_movef=0.75: 2.3852 (sd 0.0129), eld_movef=1: 2.3842 (sd 0.00681)
- **AttemptCity_Avg_E** across eld_movef: eld_movef=0: 0.0014591 (sd 7.93e-05), eld_movef=0.25: 0.001505 (sd 6.17e-05), eld_movef=0.5: 0.001521 (sd 3.4e-05), eld_movef=0.75: 0.0016174 (sd 4.23e-05), eld_movef=1: 0.0016727 (sd 6.93e-05)
- **SuccessSA_Avg_E** across eld_movef: eld_movef=0: 0.3455 (sd 0.0626), eld_movef=0.25: 0.34764 (sd 0.088), eld_movef=0.5: 0.3308 (sd 0.0404), eld_movef=0.75: 0.35649 (sd 0.0693), eld_movef=1: 0.34389 (sd 0.0425)

- **PopChange_E** across wservice: wservice=0: -100.8 (sd 17.4), wservice=0.25: -76 (sd 15), wservice=0.5: -70.2 (sd 16.3), wservice=1: -64.8 (sd 13.4), wservice=2: -80 (sd 11.5)
- **PopChange_NE** across wservice: wservice=0: -427.8 (sd 34.7), wservice=0.25: -405.4 (sd 71.9), wservice=0.5: -370.6 (sd 49.3), wservice=1: -387.6 (sd 30.5), wservice=2: -436.4 (sd 38.4)
- **AttemptSA_Avg_E** across wservice: wservice=0: 0.0022045 (sd 7.07e-05), wservice=0.25: 0.0024251 (sd 4.26e-05), wservice=0.5: 0.0024118 (sd 6.02e-05), wservice=1: 0.0024407 (sd 1.81e-05), wservice=2: 0.0024348 (sd 5.71e-05)
- **SAServiceAvg_E** across wservice: wservice=0: 2.3896 (sd 0.0128), wservice=0.25: 2.4232 (sd 0.00829), wservice=0.5: 2.4244 (sd 0.00541), wservice=1: 2.4289 (sd 0.00791), wservice=2: 2.4301 (sd 0.01)
- **AttemptCity_Avg_E** across wservice: wservice=0: 0.0016914 (sd 8.12e-05), wservice=0.25: 0.0016947 (sd 8.32e-05), wservice=0.5: 0.0016583 (sd 6.51e-05), wservice=1: 0.0016385 (sd 3.24e-05), wservice=2: 0.0017172 (sd 7.16e-05)
- **SuccessSA_Avg_E** across wservice: wservice=0: 0.32308 (sd 0.0303), wservice=0.25: 0.31995 (sd 0.0623), wservice=0.5: 0.29875 (sd 0.0464), wservice=1: 0.32575 (sd 0.0499), wservice=2: 0.32934 (sd 0.061)

- **PopChange_E** across svc_filter: svc_filter=0: -97.2 (sd 6.61), svc_filter=1: -114.4 (sd 11.1)
- **PopChange_NE** across svc_filter: svc_filter=0: -424.2 (sd 36.5), svc_filter=1: -400.6 (sd 46.1)
- **AttemptSA_Avg_E** across svc_filter: svc_filter=0: 0.0021886 (sd 3.45e-05), svc_filter=1: 0.0022869 (sd 0.000129)
- **SAServiceAvg_E** across svc_filter: svc_filter=0: 2.3868 (sd 0.0101), svc_filter=1: 2.3886 (sd 0.0151)
- **AttemptCity_Avg_E** across svc_filter: svc_filter=0: 0.0017017 (sd 4.11e-05), svc_filter=1: 0.0019464 (sd 3.96e-05)
- **SuccessSA_Avg_E** across svc_filter: svc_filter=0: 0.31376 (sd 0.0318), svc_filter=1: 0.26604 (sd 0.00638)


---

## 4. Files and reproducibility

- Full effects table (all 272 tests incl. non-significant): `effects_vs_reference_raw.csv`,
  columns: param_varied, combo, wservice, eld_movef, svc_filter, outcome, mean, ref_mean,
  pct_change, cohens_d, t_stat, p_value, n_scen, n_ref, q_value.
- Analysis code: `sensitivity_analysis.py`, class `RawSweepAnalysis`
  (methods: `effects_vs_reference()`, `rank_combinations()`, `rank_parameters()`,
  `flag_outliers()`, `plot_heatmap_split()`, `plot_dose_response()`).
- Heatmaps: signed Cohen's d, combos (rows) x outcomes (cols), color-clipped at +/-5,
  E and NE outcomes in separate panels sharing one color scale.
