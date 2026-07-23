% 2D sweep: young-old wservice x old-old wservice_old.
% young-old grid: [0.25, 0.35]
% old-old grid: [1, 1.5, 2] -- the range where the first sweep's effect on
% old-old movers' service-ratio exposure was actually visible (0.25/0.5
% barely differed from baseline; the real separation started around 1).
%
% Same fixed settings as run_wservice_old_sweep.m: eld_movef=1,
% svc_filter=1, steps=100, lu_warmup=4, lu_update_every=3,
% sa_update_every=5, resSearchLen=30.
%
% Saved to earthquakeF\agesplit70 EQ S 1 wy<young>_wo<old>_rep<n>.mat

wservice_young_grid = [0.25, 0.35];
wservice_old_grid = [1, 1.5, 2];
n_reps = 3;

steps = 100;
lu_update_every = 3;
lu_warmup = 4;
sa_update_every = 5;
resSearchLen = 30;

for wy = wservice_young_grid
    for wo = wservice_old_grid
        for r = 1:n_reps
            tag = sprintf('wy%s_wo%s_rep%d', strrep(num2str(wy), '.', ''), strrep(num2str(wo), '.', ''), r);
            fprintf('=== wservice=%.2f, wservice_old=%.2f, rep %d/%d (tag=%s) ===\n', wy, wo, r, n_reps, tag);
            run_earthquake_setting(wy, wo, 1, 1, tag, steps, lu_update_every, lu_warmup, sa_update_every, resSearchLen);
        end
    end
end

fprintf('2D sweep complete.\n');
