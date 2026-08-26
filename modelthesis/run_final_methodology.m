% Canonical reference script for the finalized thesis methodology:
% elderly_search_mode=2 (SA-level hard filter + weighted SA pick for
% out-of-SA moves, largest/most significant SA-service-ratio gain of
% every mode tested), svc_filter=1 (mode 2's within-SA hard floor).
% eld_movef is deliberately NOT used -- every reduction tested (0.33/0.5,
% 0.5/0.75, 0.6/0.8, 0.75/0.9) delayed young-old's SA-service crossover
% point enough to break full-760-day-average statistical significance;
% plain mode 2 alone already achieves significance for both age groups
% over the full run without it. Use scenario_tag to distinguish
% replicate runs (e.g. append _seedN).
scenario_tag = 'final_methodology';
run_earthquake_setting(0, 0, 1, 1, scenario_tag, 760, 1, 30, 1, 30, 20, -100, 60, 80, 0.040197164, 0.017865406, [], [], [], [], [], [], 2);
fprintf('final methodology run complete.\n');
