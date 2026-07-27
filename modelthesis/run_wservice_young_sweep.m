% Sweep young-old's OWN wservice at higher values than previously tested
% (prior sweeps only tried 0.25/0.35), to find whether/where young-old
% movers' service-ratio exposure can clear the non-elderly baseline
% (observed ~0.64-0.66 across all prior runs). Crossed with two
% wservice_old values (1.0, 1.5) to confirm the additive-no-interaction
% pattern found in the 2D sweep still holds at higher wservice.
%
% wservice grid: [0.5, 0.75, 1.0, 1.5]
% wservice_old grid: [1.0, 1.5]
% n_reps: 8 (matching the resolving power established in the 2D sweep)
%
% Same fixed settings as run_wservice_2d_sweep.m: eld_movef=1,
% svc_filter=1, steps=100, lu_warmup=4, lu_update_every=3,
% sa_update_every=5, resSearchLen=30.
%
% Saved to earthquakeF\agesplit70 EQ S 1 wy<young>_wo<old>_rep<n>.mat

wservice_young_grid = [0.5, 0.75, 1.0, 1.5];
wservice_old_grid = [1.0, 1.5];
n_reps = 8;

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

fprintf('Young-old wservice sweep complete.\n');
