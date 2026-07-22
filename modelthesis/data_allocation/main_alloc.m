%%% this script creates 5 tables:
%%% 1. Households table, 2. Individuals table, 3. Building table,
%%% 4. Assets table 5. workplaces table
%%% each table has a supplementary table that includes the column's name
%%% in order to run this script you need 2 folders:
%%% 1. file that include the raw data include:'bldgs_with_tt.csv','assets.csv','dealData.csv'
% the data file name:
file='C:\Users\allis\Documents\MATLAB\modelthesis\TVR\'; % path to working dir
parametes_name='model parameters.csv'; % model predefined marameters
NAME='data_for_model_tmine'; % output data name 
floor_hight=4; % set the average floor hieght
WS=0; % WS=0 for ALL SA; WS=0 for below SA         
working_stat = [67000011,67000012,67000013,67000014,67000015,67000017,...
                67000021,67000022,67000023,67000024,67000025,67000031,...
                67000032,67000033,67000034,67000035,67000036,67000037];

%% spatial data - the next function creates a file named 'buildings&assets.mat'
start_spatial_dataupdate(floor_hight,file,working_stat,WS);
%% create HH and individuals and save it in a file named 'HH_&_ind_data.mat'
start_HH_2018up(file);
%% distribute HH among the assets and save it in a file named 'data_after_lur.mat'
distribute_HH_2019('HH_&_ind_data.mat','buildings&assets.mat');
%% create working places according and save it in a file named 'data_after_working_place.mat'
create_work_place('data_after_lur',parametes_name,file);
%% final stage to fill the job market and save it in a file named NAME
distribute_workers('data_after_working_place',1,NAME);