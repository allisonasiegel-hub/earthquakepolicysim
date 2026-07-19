%%% this script creates 5 tables:
%%% 1. Households table, 2. Individuals table, 3. Building table,
%%% 4. Assets table 5. workplaces table
%%% each table has a supplementary table that includes the column's name
%%% in order to run this script you need 2 folders:
%%% 1. file that include the raw data include:'bldgs_with_tt.csv','assets.csv','dealData.csv'
% the data file name:
file='D:\MATLAB\Ash\ASH22\'; % path to working dir
parametes_name='parameters.csv'; % model predefined marameters
NAME='data_for_model'; % output data name 
floor_hight=4; % set the average floor hieght
WS=0; % WS=0 for ALL SA; WS=0 for below SA         
working_stat = [90000111,90000112,90000113,90000121,90000122,90000123,...
                90000131,90000132,90000133,90000211,90000212,90000213,...
                90000214,90000215,90000216,90000221,90000222,90000223,...
                90000224,90000225,90000226,90000234,90000311,90000312,...
                90000313,90000411,90000412,90000413,90000414,90000415,...
                90000421,90000422,90000423,90000431,90000432,90000433,...
                90000434,90000511,90000512,90000513,90000521,90000522,...
                90000523,90000611,90000612,90000613,90000614,90000623,...
                90000631,90000632,90000633,90000641,90000642,90000643,90000645];
%% spatial data - the next function creates a file named 'buildings&assets.mat'
start_spatial_data(floor_hight,file,working_stat,WS);
%% create HH and individuals and save it in a file named 'HH_&_ind_data.mat'
start_HH_2018(file);
%% distribute HH among the assets and save it in a file named 'data_after_lur.mat'
distribute_HH_2019('HH_&_ind_data.mat','buildings&assets.mat');
%% create working places according and save it in a file named 'data_after_working_place.mat'
create_work_place('data_after_lur',parametes_name,file);
%% final stage to fill the job market and save it in a file named NAME
distribute_workers('data_after_working_place',1,NAME);