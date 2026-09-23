# Arad — city output

**Scenario:** Arad shock baseline — no subsidy, `temp_dev_capacity_frac=0.5` (model default), `shock_step=40`, `steps=150`. 5 seed replicates (60301, 60302, 60303, 74110, 82937), all generated 2026-09-22 evening (22:38-23:59).

**Provenance caveat:** this is the most recent, internally-consistent Arad run set found in `earthquakeF/` at the time this folder was built (2026-09-23) — it was **not** independently confirmed with the session that owns Arad's work as their final/curated baseline. If that session has a different canonical run, replace the contents of `raw_mat/` and regenerate the plots with `run_arad_output_standard.py`.

**Contents:**
- `raw_mat/` — the 5 raw `.mat` output files
- `macro_trends.pdf` — full report: shelter/subsidy outcome tables, shelter-tier and displacement charts, all 30 SA_* trend pages
- `macro_trends.png` — overview grid of all 30 SA_* variables
- `shelter_tiers.png` / `total_sheltered.png` / `permanent_displacement.png` — standalone charts
- `macro_pngs/` — each SA_* variable as its own PNG
