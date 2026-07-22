%% Sensitivity sweep driver
% Three OAT axes: wservice, eld_movef, svc_filter.
% Each axis varies one parameter while holding the others at baseline.
% nReps independent replicates per setting.
%
% Metric_Track columns (23 total):
%  1=step, 2=SAServiceRatio_E, 3=SAServiceRatio_NE,
%  4=BuildServiceRatio_E, 5=BuildServiceRatio_NE,
%  6=ElderlyPop, 7=NonElderlyPop,
%  8=TotalPossAssets_SA_E, 9=TotalPossAssets_SA_NE,
%  10=NormPossAssets_SA_E, 11=NormPossAssets_SA_NE,
%  12=TotalPossAssets_City_E, 13=TotalPossAssets_City_NE,
%  14=NormPossAssets_City_E, 15=NormPossAssets_City_NE,
%  16=AttemptRate_SA_E, 17=AttemptRate_SA_NE,
%  18=AttemptRate_City_E, 19=AttemptRate_City_NE,
%  20=SuccessRate_SA_E, 21=SuccessRate_SA_NE,
%  22=SuccessRate_City_E, 23=SuccessRate_City_NE
%
% Metric_Change indices (18 total):
%  1,2=SA service delta E/NE; 3,4=building service delta E/NE;
%  5,6=pop delta E/NE;
%  7,8=norm possible assets SA delta E/NE;
%  9,10=norm possible assets city delta E/NE;
%  11,12=attempt rate SA delta E/NE;
%  13,14=attempt rate city delta E/NE;
%  15,16=success rate SA delta E/NE;
%  17,18=success rate city delta E/NE
%
% results_long also carries PopPctChange_E/NE = 100*PopChange/(initial
% subgroup pop) - raw PopChange_E/NE isn't comparable across subgroups since
% the elderly population is much smaller than non-elderly to start with.

baseline_wservice  = 0;
baseline_eld_movef = 1;
baseline_svc_filter = 0;

wservice_grid   = [0, 0.25, 0.5, 1, 2];
eld_movef_grid  = [0, 0.25, 0.5, 0.75, 1];
svc_filter_grid = [0, 1];

nReps = 5;

% runtime reduction
steps_sweep    = 90;
lu_update_every = 3;

% build settings list
settings = {};
for v = wservice_grid
    settings{end+1} = struct('param','wservice','wservice',v,'eld_movef',baseline_eld_movef,'svc_filter',baseline_svc_filter); %#ok<SAGROW>
end
for v = eld_movef_grid
    settings{end+1} = struct('param','eld_movef','wservice',baseline_wservice,'eld_movef',v,'svc_filter',baseline_svc_filter); %#ok<SAGROW>
end
for v = svc_filter_grid
    settings{end+1} = struct('param','svc_filter','wservice',baseline_wservice,'eld_movef',baseline_eld_movef,'svc_filter',v); %#ok<SAGROW>
end

rows = {};
for s = 1:length(settings)
    cfg = settings{s};
    for r = 1:nReps
        fprintf('Setting %d/%d (%s), rep %d/%d: wservice=%.2f, eld_movef=%.2f, svc_filter=%d\n', ...
            s, length(settings), cfg.param, r, nReps, cfg.wservice, cfg.eld_movef, cfg.svc_filter);

        res = run_sweep_setting(cfg.wservice, cfg.eld_movef, lu_update_every, steps_sweep, cfg.svc_filter);

        mc = res.Metric_Change;
        mt = res.Metric_Track;

        % deltas from Metric_Change
        PopChange_E    = mc(5);   PopChange_NE   = mc(6);

        % population change normalized by each subgroup's own starting count,
        % so elderly (small N) and non-elderly (large N) are comparable
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

        row = {cfg.param, cfg.wservice, cfg.eld_movef, cfg.svc_filter, r, ...
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

save('sensitivity_sweep_results.mat','results_long','results_summary');
writetable(results_long,'sensitivity_sweep_results.csv');
writetable(results_long,'sensitivity_sweep_results.xlsx');
writetable(results_summary,'sensitivity_sweep_results_summary.csv');
writetable(results_summary,'sensitivity_sweep_results_summary.xlsx');

disp(results_summary);
