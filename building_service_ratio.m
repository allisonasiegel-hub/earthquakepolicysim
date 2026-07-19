function [Build_Data,Build_Data_p]=building_service_ratio(Build_Data,Build_Data_p,Build_Distance_matrix)

%% sum number of buildings in Dm (Dm=Build_Distance_matrix)
B_in_400=[Build_Distance_matrix(:,1),nansum(Build_Distance_matrix(:,3:end)>0,2)];

%% sum number of service buildings in Dm
[locA,locB]=ismember(Build_Distance_matrix,Build_Data(:,1)); % match building ID
empty_buildings=zeros(size(locB)); % zero vector size of matching buildings
empty_buildings(locA)=Build_Data(locB(locB>0),3); % copy usage value
empty_buildings(Build_Distance_matrix==0 | isnan(Build_Distance_matrix))=nan; % NaN for 0 or <400m 
sum_service_buildings=nansum(empty_buildings(:,2:end)>1 & empty_buildings(:,2:end)<4,2); % sum rows only for combined and commercial buildings
sum_residence_buildings=nansum(empty_buildings(:,2:end)==1,2); % sum rows only for living building

Z = sum_residence_buildings ==0; % all buildings with no living buildings whitin distance 400m
service_ratio = zeros(size(Build_Data,1),1); % zero vector

service_ratio(Z)=sum_service_buildings(Z)./10; % normalization of service per building in area
service_ratio(Z==0)=sum_service_buildings(Z==0)./sum_residence_buildings(Z==0); % normalization of service per living buildings
Build_Data(:,19)=service_ratio; % append col(19)
Build_Data_p=[Build_Data_p,'service ratio']; % append header