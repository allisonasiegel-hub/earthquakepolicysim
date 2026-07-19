function [sas_data,in_out_ratio,SP]=read_sas_data(file,name)
[~,~,sas_data]=xlsread([file,name]);
in_out_ratio=[cell2mat(sas_data(2:end,1)),cell2mat(sas_data(2:end,11)),cell2mat(sas_data(2:end,12)),cell2mat(sas_data(2:end,13)),cell2mat(sas_data(2:end,14)),cell2mat(sas_data(2:end,15))]; %{'intraSAProb'}
SP={'stat','intraSAProb','intraYeshuvProb','interYeshuvProb','inOutRatio','settlement'};