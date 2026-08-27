function [Build_Data,Build_Data_p]=building_service_density(Build_Data,Build_Data_p,Build_Distance_matrix,radius_m)
% Land-area-density variant of building_service_ratio.m: sums commercial
% neighbor FLOORSPACE (Build_Data col 25) within the given radius and
% divides by the FIXED geographic area of that radius (pi*radius_m^2),
% instead of dividing by residential neighbor count/floorspace. Immune to
% the shock's effect on residential stock -- destroying housing nearby
% cannot move this metric at all, only destroying commercial buildings
% can. REPORTING-ONLY: does not feed building_score.m or new_house.m's
% elderly weighted-pick -- those still use col(19) (building_service_ratio
% or building_service_ratio_floorspace, unchanged), so elderly relocation
% behavior is completely unaffected by this. Requires Build_Data col(25)
% (floorspace) to already be populated before this is called.
[locA,locB]=ismember(Build_Distance_matrix,Build_Data(:,1)); % match building ID
usage_n=zeros(size(locB));
usage_n(locA)=Build_Data(locB(locB>0),3);
usage_n(Build_Distance_matrix==0 | isnan(Build_Distance_matrix))=nan;

floor_n=zeros(size(locB));
floor_n(locA)=Build_Data(locB(locB>0),25);
floor_n(Build_Distance_matrix==0 | isnan(Build_Distance_matrix))=nan;

is_service = usage_n(:,2:end)>1 & usage_n(:,2:end)<4; % combined and commercial buildings
sum_service_floorspace = nansum(floor_n(:,2:end).*is_service, 2); % commercial floorspace within radius

land_area = pi*radius_m^2; % fixed, same for every building
service_density = sum_service_floorspace./land_area;

Build_Data(:,26)=service_density; % append col(26)
Build_Data_p=[Build_Data_p,'service density (land-area, floorspace/m^2)'];
end
