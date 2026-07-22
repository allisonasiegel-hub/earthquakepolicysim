function create_work_place(buildings_name,parametes_name,file)
load(buildings_name)

% workers per building
% 1 - living ; 2 - combined ; 3 - commercial ; 4 - industrial ; 5 - public ; 6 - senior
[~,~,models_par]=xlsread([file,parametes_name]);
JobsPerM_ind=strcmp(models_par(:,1),'JobsPerM_ind');
JobsPerM_ind=models_par(JobsPerM_ind,2);
JobsPerM_comm=strcmp(models_par(:,1),'JobsPerM_comm');
JobsPerM_comm=models_par(JobsPerM_comm,2);

JobsPerM_pub=strcmp(models_par(:,1),'JobsPerM_pub');
JobsPerM_pub=models_par(JobsPerM_pub,2);

JobsPerM_home=strcmp(models_par(:,1),'JobsPerM_home');
JobsPerM_home=models_par(JobsPerM_home,2);
BuildingData=Build_Data;
BuildingData=BuildingData_workers(Build_Data,1,JobsPerM_home);
BuildingData=BuildingData_workers(BuildingData,6,JobsPerM_home);
BuildingData=BuildingData_workers(BuildingData,4,JobsPerM_ind);
BuildingData=BuildingData_workers(BuildingData,3,JobsPerM_comm);
BuildingData=BuildingData_workers(BuildingData,5,JobsPerM_pub);
BuildingData=BuildingData_workers(BuildingData,2,JobsPerM_comm);
Build_Data_p=[Build_Data_p,'work place'];
Build_Data=BuildingData;
clearvars -except Build_Data Build_Data_p Assets Assets_P HH_data HH_data_P Individuals_data Individuals_data_P sa_data sa_data_P is_old_old_lookup
save('data_after_working_place.mat')