%% svc_filter interaction sweep - full factorial over trimmed grids
% Full crossing of wservice x eld_movef x svc_filter, so svc_filter is
% tested both on (1) and off (0) at every wservice/eld_movef combination -
% not just at baseline like the original sensitivity_sweep_results.csv.
%
% Grids trimmed from the initial OAT sweep to keep this tractable:
%  - wservice: SAServiceAvg_E showed almost its entire total rise (2.39->2.42)
%    between 0 and 0.25, then plateaued through 0.5/1/2. So the grid here
%    covers just the region where the change actually happens: [0, 0.25].
%  - eld_movef: [0.25, 0.5, 1] per explicit request. eld_movef=0 is excluded
%    - elderly never attempt a move there, so svc_filter (which only touches
%    the elderly within-SA pool) can't have any effect to detect.
%  - svc_filter: [0, 1], crossed with every wservice/eld_movef combo above.
%
% 2 x 3 x 2 = 12 settings x nReps=10 = 180 runs - still far below a full
% factorial over the ORIGINAL grids (5 x 5 x 2 = 50 settings).
%
% Output columns match run_sensitivity_sweep.m's results_long, including the
% PopPctChange_E/NE normalization - NOT present in the original
% sensitivity_sweep_results.csv, so this is saved separately. Join on
% wservice/eld_movef/svc_filter when comparing against the original sweep.

wservice_grid   = [0, 0.25];
eld_movef_grid  = [0.25, 0.5, 1];
svc_filter_grid = [0, 1];

settings = {};
for wv = wservice_grid
    for em = eld_movef_grid
        for sf = svc_filter_grid
            settings{end+1} = struct('wservice',wv,'eld_movef',em,'svc_filter',sf); %#ok<SAGROW>
        end
    end
end

nReps = 10; % initial sweep showed several metrics (e.g. SuccessCity_Avg_E,
            % NormAssetsSA_Avg_E) had signal/noise ratios around 2-3x at
            % n=5, too close to distinguish settings reliably

% runtime settings (match original sweep so results are comparable)
steps_sweep    = 90;
lu_update_every = 3;

rows = {};
for s = 1:length(settings)
    cfg = settings{s};
    for r = 1:nReps
        fprintf('Setting %d/%d, rep %d/%d: wservice=%.2f, eld_movef=%.2f, svc_filter=%d\n', ...
            s, length(settings), r, nReps, cfg.wservice, cfg.eld_movef, cfg.svc_filter);

        res = run_sweep_setting(cfg.wservice, cfg.eld_movef, lu_update_every, steps_sweep, cfg.svc_filter);

        mc = res.Metric_Change;
        mt = res.Metric_Track;

        % deltas from Metric_Change
        PopChange_E    = mc(5);   PopChange_NE   = mc(6);

        PopInit_E  = mt(1,6);
        PopInit_NE = mt(1,7);
        if PopInit_E  > 0; PopPctChange_E  = 100*PopChange_E /PopInit_E;  else; PopPctChange_E  = NaN; end
        if PopInit_NE > 0; PopPctChange_NE = 100*PopChange_NE/PopInit_NE; else; PopPctChange_NE = NaN; end

        SAServiceDelta_E  = mc(1);  SAServiceDelta_NE  = mc(2);
        BldServiceDelta_E = mc(3);  BldServiceDelta_NE = mc(4);
        NormAssetsSA_Delta_E   = mc(7);  NormAssetsSA_Delta_NE   = mc(8);
        NormAssetsCity_Delta_E = mc(9);  NormAssetsCity_Delta_NE = mc(10);
        AttemptSA_Delta_E   = mc(11); AttemptSA_Delta_NE   = mc(12);
        AttemptCity_Delta_E = mc(13); AttemptCity_Delta_NE = mc(14);
        SuccessSA_Delta_E   = mc(15); SuccessSA_Delta_NE   = mc(16);
        SuccessCity_Delta_E = mc(17); SuccessCity_Delta_NE = mc(18);

        % whole-sim averages from Metric_Track
        SAServiceAvg_E    = nanmean(mt(:,2));  SAServiceAvg_NE   = nanmean(mt(:,3));
        BldServiceAvg_E   = nanmean(mt(:,4));  BldServiceAvg_NE  = nanmean(mt(:,5));
        NormAssetsSA_Avg_E   = nanmean(mt(:,10)); NormAssetsSA_Avg_NE   = nanmean(mt(:,11));
        NormAssetsCity_Avg_E = nanmean(mt(:,14)); NormAssetsCity_Avg_NE = nanmean(mt(:,15));
        AttemptSA_Avg_E   = nanmean(mt(:,16)); AttemptSA_Avg_NE  = nanmean(mt(:,17));
        AttemptCity_Avg_E = nanmean(mt(:,18)); AttemptCity_Avg_NE = nanmean(mt(:,19));
        SuccessSA_Avg_E   = nanmean(mt(:,20)); SuccessSA_Avg_NE  = nanmean(mt(:,21));
        SuccessCity_Avg_E = nanmean(mt(:,22)); SuccessCity_Avg_NE = nanmean(mt(:,23));

        row = {'svc_filter_full_factorial', cfg.wservice, cfg.eld_movef, cfg.svc_filter, r, ...
            PopChange_E, PopChange_NE, PopPctChange_E, PopPctChange_NE, ...
            SAServiceAvg_E, SAServiceAvg_NE, SAServiceDelta_E, SAServiceDelta_NE, ...
            BldServiceAvg_E, BldServiceAvg_NE, BldServiceDelta_E, BldServiceDelta_NE, ...
            NormAssetsCity_Avg_E, NormAssetsCity_Avg_NE, NormAssetsCity_Delta_E, NormAssetsCity_Delta_NE, ...
            NormAssetsSA_Avg_E, NormAssetsSA_Avg_NE, NormAssetsSA_Delta_E, NormAssetsSA_Delta_NE, ...
            AttemptSA_Avg_E, AttemptSA_Avg_NE, AttemptSA_Delta_E, AttemptSA_Delta_NE, ...
            AttemptCity_Avg_E, AttemptCity_Avg_NE, AttemptCity_Delta_E, AttemptCity_Delta_NE, ...
            SuccessSA_Avg_E, SuccessSA_Avg_NE, SuccessSA_Delta_E, SuccessSA_Delta_NE, ...
            SuccessCity_Avg_E, SuccessCity_Avg_NE, SuccessCity_Delta_E, SuccessCity_Delta_NE};
        rows(end+1,:) = row; %#ok<SAGROW>
    end
end

varNames = {'ParamVaried','wservice','eld_movef','svc_filter','Replicate', ...
    'PopChange_E','PopChange_NE','PopPctChange_E','PopPctChange_NE', ...
    'SAServiceAvg_E','SAServiceAvg_NE','SAServiceDelta_E','SAServiceDelta_NE', ...
    'BldServiceAvg_E','BldServiceAvg_NE','BldServiceDelta_E','BldServiceDelta_NE', ...
    'NormAssetsCity_Avg_E','NormAssetsCity_Avg_NE','NormAssetsCity_Delta_E','NormAssetsCity_Delta_NE', ...
    'NormAssetsSA_Avg_E','NormAssetsSA_Avg_NE','NormAssetsSA_Delta_E','NormAssetsSA_Delta_NE', ...
    'AttemptSA_Avg_E','AttemptSA_Avg_NE','AttemptSA_Delta_E','AttemptSA_Delta_NE', ...
    'AttemptCity_Avg_E','AttemptCity_Avg_NE','AttemptCity_Delta_E','AttemptCity_Delta_NE', ...
    'SuccessSA_Avg_E','SuccessSA_Avg_NE','SuccessSA_Delta_E','SuccessSA_Delta_NE', ...
    'SuccessCity_Avg_E','SuccessCity_Avg_NE','SuccessCity_Delta_E','SuccessCity_Delta_NE'};

results_long = cell2table(rows, 'VariableNames', varNames);

% per-setting summary: mean and std across the nReps replicates for each
% wservice/eld_movef/svc_filter combination (GroupCount = number of reps
% that went into each row, i.e. nReps unless a run errored out)
metricVars = varNames(6:end);
results_summary = groupsummary(results_long, {'ParamVaried','wservice','eld_movef','svc_filter'}, ...
    {'mean','std'}, metricVars);

save('svc_filter_interaction_results.mat','results_long','results_summary');
writetable(results_long,'svc_filter_interaction_results.csv');
writetable(results_long,'svc_filter_interaction_results.xlsx');
writetable(results_summary,'svc_filter_interaction_results_summary.csv');
writetable(results_summary,'svc_filter_interaction_results_summary.xlsx');

disp(results_summary);
