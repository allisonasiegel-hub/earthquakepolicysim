% Extends run_wservice_2d_sweep.m from n=3 to n=8 replicates per grid
% cell (adds reps 4-8; reps 1-3 already exist on disk and are not
% rerun). Brings total to 18 cells x 8 reps = 144 runs.
%
% Rationale: sweep_significance_test_2d.py showed n=3 could not resolve
% any pairwise comparison in the narrow [1, 1.5, 2] grid, even for the
% largest observed effect (old-old, wservice=0.35, 1.0 vs 2.0, Cohen's
% d~1.2). A two-sample t-test needs roughly n~11/d^2 per group for 80%
% power at alpha=0.05 -- for d=1.2 that's ~11 per group. n=8 total
% (roughly +5 on top of the existing 3) is a bounded middle ground:
% meaningfully more power than n=3 without a 5-hour runtime.
%
% Same fixed settings as run_wservice_2d_sweep.m.
%
% Saved to earthquakeF\agesplit70 EQ S 1 wy<young>_wo<old>_rep<n>.mat

wservice_young_grid = [0.25, 0.35];
wservice_old_grid = [1, 1.5, 2];
extra_reps = [4, 5, 6, 7, 8];

steps = 100;
lu_update_every = 3;
lu_warmup = 4;
sa_update_every = 5;
resSearchLen = 30;

for wy = wservice_young_grid
    for wo = wservice_old_grid
        for r = extra_reps
            tag = sprintf('wy%s_wo%s_rep%d', strrep(num2str(wy), '.', ''), strrep(num2str(wo), '.', ''), r);
            fprintf('=== wservice=%.2f, wservice_old=%.2f, rep %d (tag=%s) ===\n', wy, wo, r, tag);
            run_earthquake_setting(wy, wo, 1, 1, tag, steps, lu_update_every, lu_warmup, sa_update_every, resSearchLen);
        end
    end
end

fprintf('2D sweep extra reps complete.\n');
