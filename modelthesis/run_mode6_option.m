% Alternative-option reference script: elderly_search_mode=6 (hard
% filters at both levels, same as mode 2's structure, but SA choice is
% plain random for both age groups -- only old-old gets weighted asset
% selection, both within-SA and within the plain-picked SA on a
% between-SA move). svc_filter=1 (mode 6 relies on the same hard
% building-level floor mode 2 uses).
%
% NOT the finalized methodology -- kept here as a documented alternative.
% Tested n=4: old-old reliably clears non-elderly on SA service ratio,
% but young-old is a coin flip (2/4 replicates), and the success-rate
% cost is nearly as large as mode 2's despite dropping the weighted SA
% pick -- confirms the cost comes from the hard filters themselves, not
% the weighting. See run_final_methodology.m for the actual finalized
% config (plain mode 2, no eld_movef).
%
% Use scenario_tag to distinguish replicate runs (e.g. append _seedN).
scenario_tag = 'mode6_option';
run_earthquake_setting(0, 0, 1, 1, scenario_tag, 760, 1, 30, 1, 30, 20, -100, 60, 80, 0.040197164, 0.017865406, [], [], [], [], [], [], 6);
fprintf('mode6 option run complete.\n');
