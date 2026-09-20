"""
Analyze the subsidy policy sweep (run_subsidy_sweep.sh's manifest).

For each of the 9 (subsidy_residents_mode, subsidy_businesses_mode) combos,
averaged across the 2 matched-seed replicates:
  - number of households supported (n_hh_subsidized_total)
  - total aid distributed (total_aid_distributed)
  - number of businesses supported (n_businesses_subsidized_total)
  - households prevented from displacement: matched-seed difference vs the
    (0,0) no-subsidy baseline's n_permanently_displaced_total (same seed) -
    a positive number means fewer households were displaced under this
    combo than under no subsidy at all, with the same random draws.
  - jobs saved: matched-seed difference in the final SA_WP (total
    workplace count) vs the (0,0) baseline, same seed - a positive number
    means more jobs existed at the end of the run than under no subsidy.

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
        'n_permanently_displaced_total', 'SA_WP', 'subsidy_residents_mode', 'subsidy_businesses_mode',
        'rng_seed',
    ])
    return {
        'n_hh': float(np.asarray(d['n_hh_subsidized_total']).item()),
        'aid': float(np.asarray(d['total_aid_distributed']).item()),
        'n_biz': float(np.asarray(d['n_businesses_subsidized_total']).item()),
        'perm_displaced': float(np.asarray(d['n_permanently_displaced_total']).item()),
        'sa_wp_final': float(np.asarray(d['SA_WP'])[:, -1].sum()),
        'r_mode': int(np.asarray(d['subsidy_residents_mode']).item()),
        'b_mode': int(np.asarray(d['subsidy_businesses_mode']).item()),
        'seed': int(np.asarray(d['rng_seed']).item()),
    }


def main():
    manifest_path = sys.argv[1]
    rows = []
    with open(manifest_path, newline='') as f:
        for rec in csv.DictReader(f):
            fname = rec['filename'].strip('"')
            if not fname or rec['exit_code'] != '0':
                print(f"[skip] seed={rec['seed']} R={rec['resid_mode']} B={rec['biz_mode']} "
                      f"(exit_code={rec['exit_code']}, file={fname!r})")
                continue
            rows.append(load_row(fname))

    by_combo = {}
    for r in rows:
        by_combo.setdefault((r['r_mode'], r['b_mode']), []).append(r)

    baseline_by_seed = {r['seed']: r for r in by_combo.get((0, 0), [])}
    if len(baseline_by_seed) < 2:
        print(f"[warn] only {len(baseline_by_seed)} baseline (0,0) replicate(s) found - "
              f"prevented/saved columns need a matched-seed baseline for every seed used elsewhere.")

    print()
    header = (f"{'R mode':<8} {'B mode':<8} {'n':>3} {'HH supported':>13} {'Total aid ($)':>15} "
              f"{'Biz supported':>13} {'HH prevented':>13} {'Jobs saved':>11}")
    print(header)
    print('-' * len(header))

    for (rm, bm), recs in sorted(by_combo.items()):
        n_hh = np.mean([r['n_hh'] for r in recs])
        aid = np.mean([r['aid'] for r in recs])
        n_biz = np.mean([r['n_biz'] for r in recs])

        prevented = []
        saved = []
        for r in recs:
            base = baseline_by_seed.get(r['seed'])
            if base is None:
                continue
            prevented.append(base['perm_displaced'] - r['perm_displaced'])
            saved.append(r['sa_wp_final'] - base['sa_wp_final'])
        prevented_mean = np.mean(prevented) if prevented else float('nan')
        saved_mean = np.mean(saved) if saved else float('nan')

        print(f"{MODE_LABEL[rm]:<8} {MODE_LABEL[bm]:<8} {len(recs):>3} {n_hh:>13,.0f} {aid:>15,.0f} "
              f"{n_biz:>13,.1f} {prevented_mean:>13,.1f} {saved_mean:>11,.1f}")

    print()
    print("HH prevented / Jobs saved are matched-seed differences vs the (0,0) no-subsidy baseline")
    print("(same rng_seed both sides) - positive means the subsidy helped.")


if __name__ == '__main__':
    main()
