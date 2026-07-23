% Sweep: old-old (70+) service-preference weight, holding young-old
% (65-69) wservice fixed at 0.25. Tests whether giving old-old households
% a stronger service-accessibility preference changes their housing
% search outcomes differently than young-old households.
%
% Fixed: wservice=0.25 (young-old), eld_movef=1 (no elderly movement
% dampening), svc_filter=1, steps=100, lu_warmup=4, lu_update_every=3,
% sa_update_every=5, resSearchLen=30 -- matches the validated settings
% from the baseline/behavioral comparison runs.
%
% Each (wservice_old, replicate) combination calls run_earthquake_setting
% once (isolated function workspace per call, safe to loop). Saved to
% earthquakeF\agesplit70 EQ S 1 wsold<value>_rep<n>.mat

wservice_young = 0.25;
wservice_old_grid = [0.25, 0.5, 1, 2]; % 0.25 = same as young-old (control)
n_reps = 3;

steps = 100;
lu_update_every = 3;
lu_warmup = 4;
sa_update_every = 5;
resSearchLen = 30;

for v = wservice_old_grid
    for r = 1:n_reps
        tag = sprintf('wsold%s_rep%d', strrep(num2str(v), '.', ''), r);
        fprintf('=== wservice_old=%.2f, rep %d/%d (tag=%s) ===\n', v, r, n_reps, tag);
        run_earthquake_setting(wservice_young, v, 1, 1, tag, steps, lu_update_every, lu_warmup, sa_update_every, resSearchLen);
    end
end

fprintf('Sweep complete.\n');
