% Generates the initial Arad dataset (spatial + HH/individuals + assets +
% workplaces) from the raw Arad/ source data, which was not yet ported to
% a data_for_model_*.mat file (unlike JER/TVR/ASH22/BS08).
%
% Arad/ already carries the raw files under their generic hardcoded names
% (assets_B7_Final.csv, dealdataB7.csv, bldgs_height_tt.csv, sa_data_b7.csv,
% USG_CODE_keys.csv, Income_zidon.xlsx, model parameters.csv), so no
% renaming was needed - same situation as BS08.
%
% working_stat: the 6 statistical-area codes for Arad (YISHUV==25600 /
% "ערד") straight from Arad/sa_data_b7.csv's locality_stat column, and
% matching the codes already noted (commented out) in main_alloc.m. WS=0
% (matching JER/TVR/ASH/BS08) means this list is not actually used to
% filter - start_spatial_dataupdate keeps every SA present in the building
% data - but it is passed for parity with the other city driver scripts.
%
% unit_size_scale=1.256: calibrated the same way as Tiberias
% (run_regenerate_tveria_fix.m) / Beer Sheva (run_generate_beersheva.m) by
% testing candidates (calibrate_one_arad_scale.m) against a vacancy
% target of 7%. Default scale=1 gave 24.80% vacancy (12,858 assets /
% 9,669 occupied); 1.256 gives 7.02% (10,399 assets / 9,669 occupied).
%
% Mirrors main_alloc.m's 5-stage pipeline exactly.
file='C:\Users\allis\Documents\MATLAB\modellab\Arad\';
parametes_name='model parameters.csv';
NAME='data_for_model_Arad';
floor_hight=4;
WS=0;
unit_size_scale=1.256;
working_stat = [25600001,25600002,25600003,25600005,25600006,25600007];

fprintf('=== Stage 1/5: start_spatial_dataupdate (unit_size_scale=%.4f) ===\n', unit_size_scale);
start_spatial_dataupdate(floor_hight,file,working_stat,WS,unit_size_scale);
fprintf('=== Stage 2/5: start_HH_2018up ===\n');
start_HH_2018up(file);
fprintf('=== Stage 3/5: distribute_HH_2019 ===\n');
distribute_HH_2019('HH_&_ind_data.mat','buildings&assets.mat');
fprintf('=== Stage 4/5: create_work_place ===\n');
create_work_place('data_after_lur',parametes_name,file);
fprintf('=== Stage 5/5: distribute_workers ===\n');
distribute_workers('data_after_working_place',1,NAME);

fprintf('Generated dataset saved as %s.mat\n', NAME);
