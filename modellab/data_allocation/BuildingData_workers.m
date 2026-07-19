function BuildingData=BuildingData_workers(BuildingData,rescode,par)
a=BuildingData(:,3)==rescode;

workers=(BuildingData(a,7).*ceil(BuildingData(a,11)).*cell2mat(par));
BuildingData(a,17)=workers;
