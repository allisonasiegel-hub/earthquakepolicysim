"""
Standard-output driver for Arad's city_outputs folder (chat 2026-09-23).
Single scenario: Arad shock baseline (shock_step=40, steps=150, no
subsidy, temp_dev_capacity_frac=0.5 - the model's own defaults), 5 seed
replicates, all generated the evening of 2026-09-22 (22:38-23:59) as a
matched set - the most recent, internally-consistent Arad run found in
earthquakeF/ at the time this was built. NOT independently confirmed as
the Arad session's own final/curated baseline - flagged as such in the
city_outputs README.

Usage (from modellab/): python run_arad_output_standard.py
"""
import os
import plot_macro_comparison as p

ROOT = os.path.dirname(os.path.abspath(__file__))
EQ = os.path.join(ROOT, 'earthquakeF')

FILES = [
    'Aradhotels EQ S 20260922_230612 1 pid36464.mat',
    'Aradhotels EQ S 20260922_231441 1 pid29156.mat',
    'Aradhotels EQ S 20260922_234205 1 pid2976.mat',
    'Aradhotels EQ S 20260922_235031 1 pid50064.mat',
    'Aradhotels EQ S 20260922_235900 1 pid41616.mat',
]
LABEL = 'Arad shock baseline'
DESC = 'No subsidy, no shelter-capacity override (temp_dev_capacity_frac=0.5 default), shock_step=40, steps=150 - 5 seed replicates'

OUT_DIR = os.path.join(ROOT, 'city_outputs', 'Arad')


def main():
    files = [os.path.join(EQ, fn) for fn in FILES]
    missing = [f for f in files if not os.path.exists(f)]
    if missing:
        raise SystemExit(f'missing file(s): {missing}')
    print(f'[{LABEL}] {len(files)} replicate file(s)')

    macros = [p.load_macro(files)]
    shelter_by_label = {LABEL: p.load_shelter_outcomes(files)}
    subsidy_by_label = {LABEL: p.load_subsidy_outcomes(files)}
    tracks, shock_step, temp_dev_delay = p.load_shelter_tracks(files)
    scenario_tracks = [(LABEL, tracks, shock_step, temp_dev_delay)]
    aid_track, aid_shock_step, aid_temp_dev_delay = p.load_aid_track(files)
    aid_scenario_tracks = [(LABEL, aid_track, aid_shock_step, aid_temp_dev_delay)]
    markers_by_label = {LABEL: p.load_step_markers(files)}
    pattern_display = '; '.join(fn[:-4] for fn in FILES)
    city_meta, steps_meta, shock_step_meta = p.load_scenario_meta(files)
    scenario_info = [(LABEL, pattern_display, len(files), p.load_seeds(files), DESC,
                      city_meta, steps_meta, shock_step_meta)]
    labels = [LABEL]

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
