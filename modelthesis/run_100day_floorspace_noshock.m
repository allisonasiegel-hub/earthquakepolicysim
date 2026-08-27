% 100-day, no-shock run using the floorspace-corrected model
% (run_model_earthquake_floorspace.m / run_earthquake_setting_floorspace.m):
% every building-count-based service calculation (building-level ratio,
% SA-level ratio, plus the new density metrics) now uses floorspace
% instead. Finalized methodology (elderly_search_mode=2, svc_filter=1),
% use_staggered_relocation explicitly off (matching the prior mode1
% floorspace retest), no shock (default shock_step=900, well past day 100).
run_earthquake_setting_floorspace(0, 0, 1, 1, '100day_floorspace_noshock', 100, 1, 30, 1, 30, 20, -100, 60, 80, 0.040197164, 0.017865406, [], [], [], [], [], [], 2, [], [], [], 0);
fprintf('100day floorspace no-shock run complete.\n');
