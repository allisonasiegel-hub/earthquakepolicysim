"""
shock_delta_report.py
======================
Compares one or more shock scenarios against a single fixed baseline, all
using the FINALIZED methodology (elderly_search_mode=2, svc_filter=1, no
eld_movef -- see HANDOVER.md's quick-reference section / run_final_
methodology.m). Built for Allison's Tiberias ABM thesis project -- see
CLAUDE.md in the repo root and standard_report.py in this folder for full
project context.

DESIGNED TO BE CALLABLE FROM A FRESH CHAT SESSION WITH ZERO PRIOR CONTEXT.

Workflow this supports: the methodology (mode 2) is fixed and no longer
varies -- what varies is the SHOCK SCENARIO. Planned scenarios: a no-shock
baseline (mode 2, no earthquake -- the default --baseline below), a shock
with no intervention, and a shock with some recovery intervention (subsidy/
shelter policy toggles in run_model_earthquake.m -- subsidy_residents,
displaced_shelter, etc. -- not yet exposed as run_earthquake_setting.m
arguments as of this writing; add them there first if you want to run an
intervention variant, then pass its output's scenario_tag as one of the
positional args below). Every scenario passed in is compared against the
SAME baseline -- there is no more per-mode pairing.

Metrics reported (same 6 as standard_report.py's table -- "assets, success
rates, and service levels"):
    SA service level, Building service level      (service levels)
    SA success rate, City success rate             (success rates)
    Norm. assets SA, Norm. assets city              (assets)
...for each population group: non-senior, young-senior (65-69), old-senior
(70+).

IMPORTANT CAVEAT -- unequal run lengths: shock runs so far are 400-day runs
(shock triggers day 100, per run_shock_mode2.m); the no-shock baseline
(760day_mode2*) is 760-day. To keep the comparison fair, both sides of
every pair are truncated to the SAME number of days (whichever is shorter)
before averaging -- so the baseline average is really "what the no-shock
run looked like over the same day range the shock run covers", not its own
full-run average. This is printed in the output so it's never silently
wrong. If different scenarios passed in the same command have different
lengths, each is still paired against the (possibly differently-truncated)
baseline independently and correctly -- truncation is computed per pair.

Significance: if a scenario has >=2 replicates AND the baseline has >=2
replicates, reports a Welch's t-test p-value on the delta (per group, per
metric) and marks p<0.05 with an asterisk. Currently both the shock runs
and baseline may have only 1-10 replicates depending on what's been run --
check the printed n counts.

USAGE (run from the modelthesis/ directory; or pass --root):
    python analysis_scripts/shock_delta_report.py shock_mode2
    python analysis_scripts/shock_delta_report.py shock_mode2 shock_mode2_subsidy
    python analysis_scripts/shock_delta_report.py shock_mode2 --baseline 760day_mode2

Output: analysis_scripts/reports/shock_delta/<scenario>_vs_<baseline>.md
(printed to console too).
"""

from __future__ import annotations

import argparse
import os
import sys

import numpy as np
from scipy import stats

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from standard_report import find_files, load_metric_tracks, METRICS, HERE  # noqa: E402

DEFAULT_BASELINE = '760day_mode2'  # mode 2, no shock -- the finalized methodology's own reference


def per_rep_avg_truncated(tracks, col, n_days):
    return np.array([np.nanmean(mt[:n_days, col]) for mt in tracks])


def build_delta_rows(scenario_tracks, baseline_tracks):
    n_days = min(min(mt.shape[0] for mt in scenario_tracks), min(mt.shape[0] for mt in baseline_tracks))
    rows = []
    for mname, c_ne, c_yo, c_oo in METRICS:
        row = {'metric': mname}
        for label, col in [('ne', c_ne), ('yo', c_yo), ('oo', c_oo)]:
            scen_vals = per_rep_avg_truncated(scenario_tracks, col, n_days)
            base_vals = per_rep_avg_truncated(baseline_tracks, col, n_days)
            delta = np.mean(scen_vals) - np.mean(base_vals)
            row[f'{label}_scenario'] = np.mean(scen_vals)
            row[f'{label}_baseline'] = np.mean(base_vals)
            row[f'{label}_delta'] = delta
            if len(scen_vals) >= 2 and len(base_vals) >= 2:
                _, p = stats.ttest_ind(scen_vals, base_vals, equal_var=False)
                row[f'{label}_p'] = p
            else:
                row[f'{label}_p'] = None
        rows.append(row)
    return rows, n_days


def render_md(rows, scenario_name, baseline_name, n_scenario, n_baseline, n_days):
    lines = [
        f'## {scenario_name} vs. {baseline_name} (both truncated to first {n_days} days)',
        f'scenario replicates: n={n_scenario}   baseline replicates: n={n_baseline}',
        '',
        '| Metric | Group | Scenario | Baseline | Delta (scenario - baseline) |',
        '|---|---|---|---|---|',
    ]
    for r in rows:
        for label, name in [('ne', 'Non-senior'), ('yo', 'Young-senior'), ('oo', 'Old-senior')]:
            p = r[f'{label}_p']
            star = '*' if (p is not None and p < 0.05) else ''
            p_str = f' (p={p:.4f})' if p is not None else ' (n<2 on one side, no p-value)'
            lines.append(
                f"| {r['metric']} | {name} | {r[f'{label}_scenario']:.4f} | {r[f'{label}_baseline']:.4f} "
                f"| {r[f'{label}_delta']:+.4f}{star}{p_str} |"
            )
    lines.append('')
    lines.append("\\* p < 0.05 (Welch's two-sample t-test, scenario vs. baseline replicates, same group/metric) -- only computed when both sides have >=2 replicates")
    return '\n'.join(lines)


def run_one(root, scenario_pattern, baseline_pattern, out_root):
    scenario_files = find_files(root, scenario_pattern)
    baseline_files = find_files(root, baseline_pattern)
    if not scenario_files:
        raise SystemExit(f'No files found for scenario "{scenario_pattern}" (pattern "{scenario_pattern}*") under {root}/earthquakeF/')
    if not baseline_files:
        raise SystemExit(f'No files found for baseline "{baseline_pattern}" (pattern "{baseline_pattern}*") under {root}/earthquakeF/')

    scenario_tracks = load_metric_tracks(scenario_files)
    baseline_tracks = load_metric_tracks(baseline_files)
    rows, n_days = build_delta_rows(scenario_tracks, baseline_tracks)

    out_dir = os.path.join(out_root, 'shock_delta')
    os.makedirs(out_dir, exist_ok=True)
    md = render_md(rows, scenario_pattern, baseline_pattern, len(scenario_files), len(baseline_files), n_days)
    out_name = f'{scenario_pattern}_vs_{baseline_pattern}.md'.replace(os.sep, '_')
    with open(os.path.join(out_dir, out_name), 'w') as f:
        f.write(md + '\n')
    print(md)
    print()
    print(f'[done] {scenario_pattern} vs {baseline_pattern} -> {os.path.abspath(os.path.join(out_dir, out_name))}')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('scenarios', nargs='+', help='scenario file pattern(s) to compare against the baseline, e.g. shock_mode2 shock_mode2_subsidy')
    ap.add_argument('--baseline', default=DEFAULT_BASELINE, help=f'baseline file pattern every scenario is compared against (default: {DEFAULT_BASELINE}, i.e. mode 2 with no shock)')
    ap.add_argument('--root', default=os.path.dirname(HERE), help='project root containing earthquakeF/ (default: parent of this script\'s dir)')
    ap.add_argument('--out', default=os.path.join(HERE, 'reports'), help='output directory (default: analysis_scripts/reports)')
    args = ap.parse_args()

    for s in args.scenarios:
        run_one(args.root, s, args.baseline, args.out)


if __name__ == '__main__':
    main()
