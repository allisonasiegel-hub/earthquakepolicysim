% Baseline (no-shock) driver: Ashkelon, hotels dataset. Companion to
% run_ashkelon_shock_step25_150.m for a matched baseline-vs-shock
% comparison pair -- same steps=150, same lamda (city config block),
% just without a shock (shock_step stays at the script's own default of
% 900, well past the 150-step run length, so it never fires). See the
% README's "Validated shock scenario configuration" section for why
% steps=150 was chosen.
%
% n_sims=5: runs 5 replicates in ONE process (safe here -- unlike the
% shock scenario below, this baseline has no history of the
% n_sims>=2-in-one-process crash pattern). Each run of this file produces
% a NEW batch of 5 output files (distinct run_timestamp/pid each time,
% see run_model_earthquake_shelteroverflow.m's own header) -- re-run it
% again to add another 5 replicates on top of whatever's already in
% earthquakeF/, rather than replacing them.

city = 'Ashkelon';
steps = 150;
n_sims = 5;

run('run_model_earthquake_shelteroverflow.m')
