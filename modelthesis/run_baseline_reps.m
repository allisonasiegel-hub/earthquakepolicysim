% Runs the true no-behavioral-changes baseline (wservice=0, wservice_old=0,
% svc_filter=0, eld_movef=1) with n=8 replicates, matching the n=8 used
% for the wservice=1.0/wservice_old=1.5 combo, so the population growth
% comparison has a real variance estimate on both sides instead of
% comparing against a single baseline run.
%
% Same fixed settings as the sweeps: steps=100, lu_warmup=4,
% lu_update_every=3, sa_update_every=5, resSearchLen=30.
%
% Saved to earthquakeF\agesplit70 EQ S 1 baseline_100steps_v3_rep<n>.mat

n_reps = 8;

steps = 100;
lu_update_every = 3;
lu_warmup = 4;
sa_update_every = 5;
resSearchLen = 30;

for r = 1:n_reps
    tag = sprintf('baseline_100steps_v3_rep%d', r);
    fprintf('=== baseline (wservice=0, wservice_old=0, svc_filter=0), rep %d/%d (tag=%s) ===\n', r, n_reps, tag);
    run_earthquake_setting(0, 0, 1, 0, tag, steps, lu_update_every, lu_warmup, sa_update_every, resSearchLen);
end

fprintf('Baseline replicate runs complete.\n');
