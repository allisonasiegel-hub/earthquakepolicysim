% Regenerates the full initial Tiberias dataset (spatial + HH/individuals +
% assets + workplaces) from scratch, using the CORRECTED building source
% file (TVR/bldgs_height_tveria.csv, 4165 buildings, byte-identical to
% modelthesis's validated version) swapped in for TVR/bldgs_height_tt.csv
% (3953 buildings) - old file backed up as TVR/bldgs_height_tt_old.csv.
% Also applies unit_size_scale (ported from modelthesis's identical fix,
% see start_spatial_dataupdate.m's header comment) to bring city-wide
% dwelling-unit vacancy down from ~47% toward a ~10% target, without
% touching any building's real floorspace.
%
% Mirrors main_alloc.m's own 5-stage pipeline exactly, just with the
% Tiberias-specific parameters and the corrected/scaled inputs. Existing
% data_for_model_TVR.mat/data_for_model_TVR_hotels.mat were backed up as
% *_PRE_DENSITY_FIX_BACKUP.mat before this runs.
%
% After this completes, re-run identify_hotels_TVR.m to regenerate
% data_for_model_TVR_hotels.mat from the fresh base dataset.
file='C:\Users\allis\Documents\MATLAB\modellab\TVR\';
parametes_name='model parameters.csv';
NAME='data_for_model_TVR';
floor_hight=4;
WS=0;
working_stat = [67000011,67000012,67000013,67000014,67000015,67000017,...
                67000021,67000022,67000023,67000024,67000025,67000031,...
                67000032,67000033,67000034,67000035,67000036,67000037];

% unit_size_scale: starting from modelthesis's validated 1.7806 (calibrated
% against the same corrected building file for a 17,450-household dataset,
% ~10% target). modellab's Tiberias household count (17,966) and asset
% count (34,162 pre-fix) are close but not identical, so re-check the
% resulting vacancy after this run and refine if it's not close to 10%.
unit_size_scale=1.7806;

fprintf('=== Stage 1/5: start_spatial_dataupdate (corrected bldgs_height CSV, unit_size_scale=%.4f) ===\n', unit_size_scale);
start_spatial_dataupdate(floor_hight,file,working_stat,WS,unit_size_scale);
fprintf('=== Stage 2/5: start_HH_2018up ===\n');
start_HH_2018up(file);
fprintf('=== Stage 3/5: distribute_HH_2019 ===\n');
distribute_HH_2019('HH_&_ind_data.mat','buildings&assets.mat');
fprintf('=== Stage 4/5: create_work_place ===\n');
create_work_place('data_after_lur',parametes_name,file);
fprintf('=== Stage 5/5: distribute_workers ===\n');
distribute_workers('data_after_working_place',1,NAME);

fprintf('Regenerated dataset saved as %s.mat\n', NAME);
