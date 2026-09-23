"""
Standard-output driver for the no-subsidy capacity comparison only (chat
2026-09-23) - modes 1-3 of the full sweep (no-shock baseline, capacity
0.5, capacity 1.0), all at subsidy_residents_mode=0. Split out from
run_subsidy_capacity_standard_output.py's 7-mode report because modes 4-7
(residents subsidy on) are currently confounded by a mid-sweep upstream
edit to HH_subsidy_targeted.m (the wage-yardstick fix was reverted by
another session at 2026-09-22 22:08:07, splitting seed 74110's mode-5 and
mode-6 combos, and every combo for seeds 82937/30581, across two code
versions) - a fresh rerun of those is in progress. Modes 1-3 are
unaffected: subsidy_residents_mode=0 never touches the reverted code path
at all, so they're valid to report now regardless of that timing issue.

Usage (from modellab/): python run_capacity_only_standard_output.py
"""
import os
import plot_macro_comparison as p

ROOT = os.path.dirname(os.path.abspath(__file__))
EQ = os.path.join(ROOT, 'earthquakeF')

SCENARIOS = [
    ('mode 1', 'No-shock baseline (reference) - no subsidy, no shelter policy, shock never fires', [
        'hotels EQ S 20260923_011429 1 pid31812.mat',
        'hotels EQ S 20260923_011705 1 pid43776.mat',
        'hotels EQ S 20260923_011937 1 pid40328.mat',
    ]),
    ('mode 2', 'No subsidy, limited shelter capacity (temp_dev_capacity_frac=0.5)', [
        'hotels EQ S 20260923_001543 1 pid41564.mat',
        'hotels EQ S 20260923_001856 1 pid40196.mat',
        'hotels EQ S 20260923_002203 1 pid12712.mat',
    ]),
    ('mode 3', 'No subsidy, full shelter capacity (temp_dev_capacity_frac=1.0)', [
        'hotels EQ S 20260922_215927 1 pid56284.mat',
        'hotels EQ S 20260922_221642 1 pid23612.mat',
        'hotels EQ S 20260922_232638 1 pid52928.mat',
    ]),
]

OUT_DIR = os.path.join(ROOT, 'plots_capacity_only')


def main():
    macros, labels, shelter_by_label, subsidy_by_label = [], [], {}, {}
    scenario_tracks, aid_scenario_tracks = [], []
    markers_by_label = {}
    scenario_info = []

    for label, desc, filenames in SCENARIOS:
        files = [os.path.join(EQ, fn) for fn in filenames]
        missing = [f for f in files if not os.path.exists(f)]
        if missing:
            raise SystemExit(f'[{label}] missing file(s): {missing}')
        print(f'[{label}] {len(files)} replicate file(s)')
        macros.append(p.load_macro(files))
        shelter_by_label[label] = p.load_shelter_outcomes(files)
        subsidy_by_label[label] = p.load_subsidy_outcomes(files)
        tracks, shock_step, temp_dev_delay = p.load_shelter_tracks(files)
        scenario_tracks.append((label, tracks, shock_step, temp_dev_delay))
        aid_track, aid_shock_step, aid_temp_dev_delay = p.load_aid_track(files)
        aid_scenario_tracks.append((label, aid_track, aid_shock_step, aid_temp_dev_delay))
        markers_by_label[label] = p.load_step_markers(files)
        pattern_display = '; '.join(fn[:-4] if fn.endswith('.mat') else fn for fn in filenames)
        city_meta, steps_meta, shock_step_meta = p.load_scenario_meta(files)
        scenario_info.append((label, pattern_display, len(files), p.load_seeds(files), desc,
                               city_meta, steps_meta, shock_step_meta))
        labels.append(label)

    os.makedirs(OUT_DIR, exist_ok=True)
    title_suffix = ''

    p.plot_grid(macros, labels, os.path.join(OUT_DIR, 'macro_trends.png'), title_suffix, markers_by_label=markers_by_label)
    p.plot_pdf_and_pngs(macros, labels, shelter_by_label, os.path.join(OUT_DIR, 'macro_trends.pdf'),
                         os.path.join(OUT_DIR, 'macro_pngs'), title_suffix,
                         scenario_tracks=scenario_tracks, subsidy_by_label=subsidy_by_label,
                         aid_scenario_tracks=aid_scenario_tracks, markers_by_label=markers_by_label,
                         scenario_info=scenario_info, show_pattern_column=False)
    p.plot_shelter_timeseries(scenario_tracks, OUT_DIR, title_suffix)
    p.plot_aid_timeseries(aid_scenario_tracks, OUT_DIR, title_suffix)
    print(f'[done] -> {OUT_DIR}')


if __name__ == '__main__':
    main()
