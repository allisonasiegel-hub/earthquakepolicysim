% 760-day, no-shock run using the floorspace-corrected model, same config
% as run_100day_floorspace_noshock.m (finalized methodology:
% elderly_search_mode=2, svc_filter=1, use_staggered_relocation=0) but
% run out to the full 760 days to see whether the day-99 crossover trend
% (old-old already above non-elderly, young-old closing fast) holds at a
% converged/settled state.
run_earthquake_setting_floorspace(0, 0, 1, 1, '760day_floorspace_noshock', 760, 1, 30, 1, 30, 20, -100, 60, 80, 0.040197164, 0.017865406, [], [], [], [], [], [], 2, [], [], [], 0);
fprintf('760day floorspace no-shock run complete.\n');
