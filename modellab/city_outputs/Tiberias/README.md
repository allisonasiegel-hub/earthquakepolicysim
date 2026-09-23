# Tiberias — city output

**Scenarios included (modes 1-3, no subsidy):**
- Mode 1 — no-shock baseline (reference)
- Mode 2 — shock, no subsidy, limited shelter capacity (`temp_dev_capacity_frac=0.5`)
- Mode 3 — shock, no subsidy, full shelter capacity (`temp_dev_capacity_frac=1.0`)

3 seed replicates each (74110, 82937, 30581). `shock_step=25`, `steps=150`.

**Finding:** shelter capacity has no measurable effect on permanent displacement (1,269 ± 33 for both capacity settings, all 3 seeds) — see chat history for the full mechanism writeup (tier-1/tier-3 patience clocks).

**Not included yet — residents-subsidy modes (5/6):** a mid-sweep upstream edit to `HH_subsidy_targeted.m` (the "wage-yardstick fix" was reverted by another session at 2026-09-22 22:08:07, mid-run) split the original subsidy-mode sweep across two code versions. A clean rerun of all 18 combos (residents {0,5,6} x capacity {0.5,1.0} x 3 seeds) is in progress as of this push — this folder will be updated with the full 7-mode comparison once that finishes.

**Contents:**
- `raw_mat/` — the 9 raw `.mat` output files (3 modes x 3 seeds)
- `macro_trends.pdf` — full report: shelter/subsidy outcome tables, shelter-tier and displacement charts, all 30 SA_* trend pages
- `macro_trends.png` — overview grid of all 30 SA_* variables
- `shelter_tiers.png` / `total_sheltered.png` / `permanent_displacement.png` — standalone charts
- `macro_pngs/` — each SA_* variable as its own PNG
