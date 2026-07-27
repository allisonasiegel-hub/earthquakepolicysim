% One-off recovery script: reruns everything that was corrupted or
% skipped when two run_earthquake_setting.m-based sweep jobs were
% launched concurrently in this directory (they share fixed intermediate
% file paths, see the CONCURRENCY WARNING in run_earthquake_setting.m).
% All reruns here happen sequentially within this single MATLAB process,
% which is safe.

steps = 100;
lu_update_every = 3;
lu_warmup = 4;
sa_update_every = 5;
resSearchLen = 30;

% --- wy1_wo15 reps 12-16 (12 was skipped, 13-16 were contaminated) ---
for r = [12, 13, 14, 15, 16]
    tag = sprintf('wy1_wo15_rep%d', r);
    fprintf('=== wservice=1.0, wservice_old=1.5, rep %d (tag=%s) ===\n', r, tag);
    run_earthquake_setting(1.0, 1.5, 1, 1, tag, steps, lu_update_every, lu_warmup, sa_update_every, resSearchLen);
end

% --- baseline reps 1-8 (all 5 existing were contaminated and deleted) ---
for r = 1:8
    tag = sprintf('baseline_100steps_v3_rep%d', r);
    fprintf('=== baseline (wservice=0, wservice_old=0, svc_filter=0), rep %d/8 (tag=%s) ===\n', r, tag);
    run_earthquake_setting(0, 0, 1, 0, tag, steps, lu_update_every, lu_warmup, sa_update_every, resSearchLen);
end

fprintf('Recovery reruns complete.\n');
