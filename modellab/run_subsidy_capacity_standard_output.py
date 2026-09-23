"""
Standard-output driver for the household-subsidy x shelter-capacity
sweep (chat 2026-09-22/23), matching the report structure the Arad chat
established the same day: a title page (build_title_page_figure) listing
each scenario's plain-English policy description, pattern/replicate
count/seeds, with the short "mode N" label used everywhere else in the
report (charts, legends, tables).

Not using plot_macro_comparison.py's --pattern CLI directly since the
sweep's timestamps interleave combos within each seed's run block (not
separable by a single glob per combo) - explicit file lists instead, but
otherwise mirrors main()'s wiring exactly (scenario_info, markers_by_label,
etc.) so the output matches what the CLI would produce.

Usage (from modellab/): python run_subsidy_capacity_standard_output.py
"""
import os
import plot_macro_comparison as p

ROOT = os.path.dirname(os.path.abspath(__file__))
EQ = os.path.join(ROOT, 'earthquakeF')

# (label, description-for-title-page, [replicate filenames])
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
    ('mode 4', 'Residents subsidy mode 5 (decile-tiered 30/35/40% of housing cost, 4-week duration), '
               'limited shelter capacity (0.5)', [
        'hotels EQ R5 S 20260922_220238 1 pid28244.mat',
        'hotels EQ R5 S 20260922_222001 1 pid50556.mat',
        'hotels EQ R5 S 20260922_232943 1 pid34532.mat',
    ]),
    ('mode 5', 'Residents subsidy mode 5 (decile-tiered 30/35/40% of housing cost, 4-week duration), '
               'full shelter capacity (1.0)', [
        'hotels EQ R5 S 20260922_220543 1 pid33344.mat',
        'hotels EQ R5 S 20260922_222338 1 pid45748.mat',
        'hotels EQ R5 S 20260922_233245 1 pid10996.mat',
    ]),
    ('mode 6', 'Residents subsidy mode 6 (decile-tiered 10/15/20% of housing cost, 12-week duration), '
               'limited shelter capacity (0.5)', [
        'hotels EQ R6 S 20260922_220920 1 pid19940.mat',
        'hotels EQ R6 S 20260922_222636 1 pid4120.mat',
        'hotels EQ R6 S 20260922_233543 1 pid28940.mat',
    ]),
    ('mode 7', 'Residents subsidy mode 6 (decile-tiered 10/15/20% of housing cost, 12-week duration), '
               'full shelter capacity (1.0)', [
        'hotels EQ R6 S 20260922_221330 1 pid17880.mat',
        'hotels EQ R6 S 20260922_222941 1 pid53872.mat',
        'hotels EQ R6 S 20260922_233839 1 pid47560.mat',
    ]),
]

OUT_DIR = os.path.join(ROOT, 'plots_subsidy_capacity_sweep')


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
        # explicit file list, not a single glob pattern (see module
        # docstring) - report each replicate's own filename instead of a
        # (nonexistent) shared pattern string. build_title_page_figure
        # appends '*.mat' to whatever's passed here, so strip the real
        # extension first to avoid a doubled "....mat*.mat" suffix.
        pattern_display = '; '.join(fn[:-4] if fn.endswith('.mat') else fn for fn in filenames)
        city_meta, steps_meta, shock_step_meta = p.load_scenario_meta(files)
        scenario_info.append((label, pattern_display, len(files), p.load_seeds(files), desc,
                               city_meta, steps_meta, shock_step_meta))
        labels.append(label)

    os.makedirs(OUT_DIR, exist_ok=True)
    title_suffix = ''  # chat 2026-09-23: drop the "(mode 1 vs. mode 2 vs. ...)" suffix from every chart/table title

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
