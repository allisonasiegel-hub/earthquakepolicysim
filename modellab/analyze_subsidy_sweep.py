"""
Analyze the subsidy + sheltering-capacity policy sweep
(run_arad_full_subsidy_sheltering_sweep.sh's manifest, or the older
subsidy-only sweep manifests it's backward-compatible with).

For each (subsidy_residents_mode, subsidy_businesses_mode,
temp_dev_capacity_frac) combo, averaged across matched-seed replicates:
  - number of households supported (n_hh_subsidized_total)
  - total aid distributed (total_aid_distributed)
  - number of businesses supported (n_businesses_subsidized_total)
  - HH prevented (raw): matched-seed difference vs the (0,0) no-subsidy
    baseline's n_permanently_displaced_total (same seed, same
    capacity_frac) - a positive number means fewer TOTAL displacement
    EVENTS happened under this combo than under no subsidy. CAVEAT
    (found 2026-09-20, Arad business-subsidy fix investigation): this raw
    total mixes ORIGINAL residents with newly-migrated-in households who
    arrive mid-run and later leave again - a policy that increases
    housing-market churn (more people moving in AND out) without
    changing anyone's real welfare can still make this column swing
    sharply negative, purely from counting more churn events, not more
    harm. Confirmed empirically: one Arad comparison showed this column
    apparently worsen by ~2865 events while the ORIGINAL-cohort-only
    figure (next column) moved by only +225 and city-wide
    population/wage/employment were nearly identical between the two
    runs being compared.
  - HH prevented (original cohort): the same matched-seed comparison, but
    using n_original_hh_permanently_displaced_total - only households
    present at load time (excludes migrant churn). This is the
    welfare-relevant number; prefer it over the raw column above when
    they disagree. Blank/NaN for older output .mat files predating this
    metric (added 2026-09-19) - falls back gracefully, just can't compute
    a delta for those rows.
  - jobs subsidized (chat 2026-09-23, REDEFINED - this column used to be
    a matched-seed delta in final SA_WP vs the (0,0) baseline; renamed
    and changed on request, since "jobs saved" implying a counterfactual
    comparison was misleading for what's actually a straightforward
    count): CURRENT (final-step) Work_places row count at buildings that
    were EVER in businesses_subsidized_ever_ids - literally how many jobs
    sit at buildings the subsidy touched, not a running tally of every
    job-week actually subsidized. Always 0 for mode 0/off (nothing ever
    gets subsidized).
  - net jobs delta: the OLD "jobs saved" definition, kept under its own
    honest name - matched-seed difference in final SA_WP (total
    workplace count, all buildings city-wide) vs the (0,0) baseline, same
    seed and capacity_frac. A positive number means more total jobs
    existed at the end of the run than under no subsidy; this is the
    city-wide net effect, and can be (and typically is, per the Arad
    Change_LU investigation, chat 2026-09-22) negative even while "jobs
    subsidized" above is a large positive number - the subsidy can
    genuinely protect hundreds of jobs at the buildings it touches while
    the city as a whole still ends up with fewer jobs than doing nothing,
    because propping up existing buildings comes at the cost of fewer new
    commercial buildings ever getting created elsewhere.

ABSOLUTE-VALUE TABLE (chat 2026-09-22): a second table reporting each
combo's own final-state numbers directly, not deltas vs baseline -
requested after "jobs subsidized" (then still called "jobs saved") alone
masked a case where a subsidy mode had fewer total job LOSSES than
another mode but ended up with a LOWER average wage, because more of the
final job pool sat at the (typically small/struggling) buildings the
subsidy protected:
  - final jobs: SA_WP summed over all sub-areas, last step (same number
    the main table's "net jobs delta" is computed from, before
    subtracting the baseline).
  - final avg wage: mean(Individuals_data(:,14)) over working residents
    (col 15 >0 and ~=99), matching the model's own average_wage formula
    exactly (run_model_earthquake_shelteroverflow.m). Only meaningful as
    "wages excluding the household subsidy" when subsidy_residents_mode
    is 0/off for every row in the manifest - the resident subsidy adds
    directly to this same column (HH_subsidy_targeted.m, reverted to do
    so again as of chat 2026-09-22), so a mix of resident-subsidized and
    unsubsidized rows would conflate real wage effects with subsidy cash.
  - final n working: count of individuals with an active workplace.

BASELINE MATCHING (2026-09-22): when the manifest has a capacity_frac
column, the (0,0) baseline is matched by (seed, capacity_frac) together,
not seed alone - subsidy_businesses_mode=0/subsidy_residents_mode=0 was
run at EVERY capacity_frac value too (temp_dev_capacity_frac affects
sheltering dynamics independent of subsidy status), so comparing a
combo run at capacity=1.00 against a baseline run at capacity=0.50 would
conflate the two dimensions. Older manifests without a capacity_frac
column (pre-2026-09-22 subsidy-only sweeps) fall back to seed-only
matching, unchanged from before.

NO-SHOCK BASELINE ROWS (scenario=noshock, resid_mode/biz_mode/
capacity_frac=NA): reported as their own summary block (final population,
final SA_WP, mean +/-1 std across replicates) - separate from the main
grid table, since subsidy/capacity-frac don't apply without a shock.

Usage: python analyze_subsidy_sweep.py <manifest.csv>
"""
import sys
import csv
import numpy as np
import scipy.io as sio

MODE_LABEL = {0: 'off', 1: 'mode 1', 2: 'mode 2', 3: 'mode 3', 4: 'mode 4', 5: 'mode 5', 6: 'mode 6'}


def load_row(path):
    d = sio.loadmat(path, variable_names=[
        'n_hh_subsidized_total', 'total_aid_distributed', 'n_businesses_subsidized_total',
        'n_permanently_displaced_total', 'n_original_hh_permanently_displaced_total',
        'SA_WP', 'SA_POP', 'subsidy_residents_mode', 'subsidy_businesses_mode',
        'rng_seed', 'Individuals_data', 'Work_places', 'businesses_subsidized_ever_ids',
    ])
    # n_original_hh_permanently_displaced_total: added 2026-09-19, absent
    # from older output .mat files - loadmat's variable_names filter just
    # omits missing names rather than erroring, so fall back to NaN.
    orig_displaced = float(np.asarray(d['n_original_hh_permanently_displaced_total']).item()) \
        if 'n_original_hh_permanently_displaced_total' in d else float('nan')

    avg_wage_final = float('nan')
    n_working_final = float('nan')
    if 'Individuals_data' in d:
        ind = d['Individuals_data']
        working = (ind[:, 14] > 0) & (ind[:, 14] != 99)  # col15 work_place_id, col15 commuter code 99
        n_working_final = float(working.sum())
        if working.sum() > 0:
            avg_wage_final = float(ind[working, 13].mean())  # col14 income

    jobs_at_subsidized_final = float('nan')
    if 'Work_places' in d and 'businesses_subsidized_ever_ids' in d:
        biz_ids = np.asarray(d['businesses_subsidized_ever_ids']).flatten()
        wp = d['Work_places']
        jobs_at_subsidized_final = float(np.isin(wp[:, 0], biz_ids).sum()) if biz_ids.size > 0 else 0.0

    return {
        'n_hh': float(np.asarray(d['n_hh_subsidized_total']).item()) if 'n_hh_subsidized_total' in d else float('nan'),
        'aid': float(np.asarray(d['total_aid_distributed']).item()) if 'total_aid_distributed' in d else float('nan'),
        'n_biz': float(np.asarray(d['n_businesses_subsidized_total']).item()) if 'n_businesses_subsidized_total' in d else float('nan'),
        'perm_displaced': float(np.asarray(d['n_permanently_displaced_total']).item()) if 'n_permanently_displaced_total' in d else float('nan'),
        'orig_displaced': orig_displaced,
        'sa_wp_final': float(np.asarray(d['SA_WP'])[:, -1].sum()) if 'SA_WP' in d else float('nan'),
        'sa_pop_final': float(np.asarray(d['SA_POP'])[:, -1].sum()) if 'SA_POP' in d else float('nan'),
        'avg_wage_final': avg_wage_final,
        'n_working_final': n_working_final,
        'jobs_at_subsidized_final': jobs_at_subsidized_final,
        'r_mode': int(np.asarray(d['subsidy_residents_mode']).item()),
        'b_mode': int(np.asarray(d['subsidy_businesses_mode']).item()),
        'seed': int(np.asarray(d['rng_seed']).item()),
    }


def parse_capacity(raw):
    """capacity_frac field: numeric string for shock rows, 'NA' (or
    absent - older manifests) for no-shock/unknown. Returns a float or
    None."""
    if raw is None:
        return None
    raw = raw.strip()
    if raw == '' or raw.upper() == 'NA':
        return None
    try:
        return float(raw)
    except ValueError:
        return None


def fmt_cap(cap):
    return 'n/a' if cap is None else f'{cap:.2f}'


def main():
    manifest_path = sys.argv[1]
    with open(manifest_path, newline='') as f:
        reader = csv.DictReader(f)
        has_scenario_col = 'scenario' in (reader.fieldnames or [])
        has_capacity_col = 'capacity_frac' in (reader.fieldnames or [])
        recs_raw = list(reader)

    noshock_rows = []
    shock_rows = []
    for rec in recs_raw:
        fname = rec['filename'].strip('"')
        scenario = rec.get('scenario', 'shock') if has_scenario_col else 'shock'
        cap = parse_capacity(rec.get('capacity_frac')) if has_capacity_col else None
        if not fname or rec['exit_code'] != '0':
            print(f"[skip] scenario={scenario} seed={rec['seed']} R={rec.get('resid_mode')} "
                  f"B={rec.get('biz_mode')} cap={rec.get('capacity_frac')} "
                  f"(exit_code={rec['exit_code']}, file={fname!r})")
            continue
        row = load_row(fname)
        row['cap'] = cap
        if scenario == 'noshock':
            noshock_rows.append(row)
        else:
            shock_rows.append(row)

    # --- No-shock baseline summary ---
    if noshock_rows:
        pops = np.array([r['sa_pop_final'] for r in noshock_rows])
        wps = np.array([r['sa_wp_final'] for r in noshock_rows])
        print(f"=== No-shock baseline (n={len(noshock_rows)}) ===")
        print(f"Final population:  mean={np.nanmean(pops):,.0f}  std={np.nanstd(pops):,.0f}  "
              f"range=[{np.nanmin(pops):,.0f}, {np.nanmax(pops):,.0f}]")
        print(f"Final SA_WP:       mean={np.nanmean(wps):,.0f}  std={np.nanstd(wps):,.0f}  "
              f"range=[{np.nanmin(wps):,.0f}, {np.nanmax(wps):,.0f}]")
        print()

    if not shock_rows:
        return

    # --- Shock grid, grouped by (capacity_frac, r_mode, b_mode) ---
    by_combo = {}
    for r in shock_rows:
        by_combo.setdefault((r['cap'], r['r_mode'], r['b_mode']), []).append(r)

    # Baseline matched by (seed, capacity_frac) when capacity_frac is
    # present in this manifest, else by seed alone (old manifests).
    baseline_by_key = {}
    for (cap, rm, bm), recs in by_combo.items():
        if (rm, bm) == (0, 0):
            for r in recs:
                baseline_by_key[(r['seed'], cap)] = r
    n_baseline_seeds = len({k[0] for k in baseline_by_key})
    if n_baseline_seeds < 2:
        print(f"[warn] only {n_baseline_seeds} baseline (0,0) seed(s) found per capacity_frac - "
              f"prevented/saved columns need a matched-seed baseline for every seed used elsewhere.")

    print()
    header = (f"{'Cap':>5} {'R mode':<8} {'B mode':<8} {'n':>3} {'HH supported':>13} {'Total aid ($)':>15} "
              f"{'Biz supported':>13} {'HH prev(raw)':>13} {'HH prev(orig)':>14} {'Jobs subsidized':>15} {'Net jobs delta':>14}")
    print(header)
    print('-' * len(header))

    for (cap, rm, bm), recs in sorted(by_combo.items(), key=lambda kv: (kv[0][0] if kv[0][0] is not None else -1, kv[0][1], kv[0][2])):
        n_hh = np.mean([r['n_hh'] for r in recs])
        aid = np.mean([r['aid'] for r in recs])
        n_biz = np.mean([r['n_biz'] for r in recs])
        jobs_subsidized_mean = np.nanmean([r['jobs_at_subsidized_final'] for r in recs])

        prevented = []
        prevented_orig = []
        net_delta = []
        for r in recs:
            base = baseline_by_key.get((r['seed'], cap))
            if base is None:
                continue
            prevented.append(base['perm_displaced'] - r['perm_displaced'])
            if not (np.isnan(base['orig_displaced']) or np.isnan(r['orig_displaced'])):
                prevented_orig.append(base['orig_displaced'] - r['orig_displaced'])
            net_delta.append(r['sa_wp_final'] - base['sa_wp_final'])
        prevented_mean = np.mean(prevented) if prevented else float('nan')
        prevented_orig_mean = np.mean(prevented_orig) if prevented_orig else float('nan')
        net_delta_mean = np.mean(net_delta) if net_delta else float('nan')

        print(f"{fmt_cap(cap):>5} {MODE_LABEL[rm]:<8} {MODE_LABEL[bm]:<8} {len(recs):>3} {n_hh:>13,.0f} {aid:>15,.0f} "
              f"{n_biz:>13,.1f} {prevented_mean:>13,.1f} {prevented_orig_mean:>14,.1f} {jobs_subsidized_mean:>15,.1f} {net_delta_mean:>14,.1f}")

    print()
    print("HH prev(raw) is a matched-seed (and matched-capacity_frac, when present) difference vs the")
    print("(0,0) no-subsidy baseline - positive means the subsidy helped. HH prev(orig) is the same")
    print("comparison restricted to ORIGINAL households (excludes migrant churn) - the welfare-relevant")
    print("number; prefer it over HH prev(raw) when they disagree (see this script's header docstring).")
    print("Jobs subsidized is a plain count (see header docstring), not a baseline comparison. Net jobs")
    print("delta IS the matched-seed baseline comparison (the metric this column used to be called")
    print("'Jobs saved' for) - the two can and often do point opposite directions.")

    # --- Absolute-value table (chat 2026-09-22, see header docstring) ---
    print()
    print("=== Absolute final-state values (not deltas vs baseline) ===")
    header2 = (f"{'Cap':>5} {'R mode':<8} {'B mode':<8} {'n':>3} {'Final jobs':>12} {'Final avg wage':>15} "
               f"{'Final n working':>16}")
    print(header2)
    print('-' * len(header2))
    for (cap, rm, bm), recs in sorted(by_combo.items(), key=lambda kv: (kv[0][0] if kv[0][0] is not None else -1, kv[0][1], kv[0][2])):
        final_jobs = np.nanmean([r['sa_wp_final'] for r in recs])
        avg_wage = np.nanmean([r['avg_wage_final'] for r in recs])
        n_working = np.nanmean([r['n_working_final'] for r in recs])
        print(f"{fmt_cap(cap):>5} {MODE_LABEL[rm]:<8} {MODE_LABEL[bm]:<8} {len(recs):>3} {final_jobs:>12,.1f} "
              f"{avg_wage:>15,.1f} {n_working:>16,.1f}")
    print()
    print("Final avg wage only excludes the household subsidy's effect on col 14 when")
    print("subsidy_residents_mode=0/off for every row above - see this script's header docstring.")


if __name__ == '__main__':
    main()
