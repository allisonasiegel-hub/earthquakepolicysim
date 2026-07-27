% Adds reps 9-16 to the single combo wservice=1.0, wservice_old=1.5,
% bringing it from n=8 to n=16. At n=8, young-old vs non-elderly was
% borderline (t=2.18, p=0.053, Cohen's d~1.1). A two-sample t-test needs
% roughly n~16/d^2 per group for 80% power at alpha=0.05 -- for d~1.1
% that's ~13 per group, so n=16 gives a comfortable margin.
%
% Same fixed settings as run_wservice_young_sweep.m.
%
% Saved to earthquakeF\agesplit70 EQ S 1 wy1_wo15_rep<n>.mat

wy = 1.0;
wo = 1.5;
extra_reps = [9, 10, 11, 12, 13, 14, 15, 16];

steps = 100;
lu_update_every = 3;
lu_warmup = 4;
sa_update_every = 5;
resSearchLen = 30;

for r = extra_reps
    tag = sprintf('wy%s_wo%s_rep%d', strrep(num2str(wy), '.', ''), strrep(num2str(wo), '.', ''), r);
    fprintf('=== wservice=%.2f, wservice_old=%.2f, rep %d (tag=%s) ===\n', wy, wo, r, tag);
    run_earthquake_setting(wy, wo, 1, 1, tag, steps, lu_update_every, lu_warmup, sa_update_every, resSearchLen);
end

fprintf('wservice=1.0/wservice_old=1.5 extra reps complete.\n');
