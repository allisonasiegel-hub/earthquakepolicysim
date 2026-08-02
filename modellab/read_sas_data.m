function [sas_data,in_out_ratio,SP]=read_sas_data(file,name)
[~,~,sas_data]=xlsread([file,name]);
in_out_ratio=[cell2mat(sas_data(2:end,1)),cell2mat(sas_data(2:end,11)),cell2mat(sas_data(2:end,12)),cell2mat(sas_data(2:end,13)),cell2mat(sas_data(2:end,14)),cell2mat(sas_data(2:end,15))]; %{'intraSAProb'}
% intraSAProb (col 2) and intraYeshuvProb (col 3) are daily move
% probabilities, used directly as a per-step threshold in who_is_moving.m
% (K=2/K=3) - converted to weekly here since steps now represent weeks
% (see day_to_week_step_rescaling_audit.md item 2). interYeshuvProb
% (col 4) is loaded but never actually consumed anywhere in this
% codebase, so left as-is. inOutRatio (col 5) is a different conversion,
% already handled in migration_19.m (/365 -> /52).
in_out_ratio(:,2)=1-(1-in_out_ratio(:,2)).^7;
in_out_ratio(:,3)=1-(1-in_out_ratio(:,3)).^7;
SP={'stat','intraSAProb','intraYeshuvProb','interYeshuvProb','inOutRatio','settlement'};