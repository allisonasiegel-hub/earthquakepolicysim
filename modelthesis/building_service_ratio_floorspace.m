function [Build_Data,Build_Data_p]=building_service_ratio_floorspace(Build_Data,Build_Data_p,Build_Distance_matrix)
% Floorspace-weighted variant of building_service_ratio.m: sums
% commercial/residential FLOORSPACE (Build_Data col 25) of neighbor
% buildings within the given radius, instead of counting neighbor
% buildings 1-for-1 regardless of size. Forked into a separate function
% (not a parameter toggle on the original) because Build_Data(:,19) is
% read by building_score.m and new_house.m's elderly weighted-pick, not
% just reported as a metric -- this is a real behavioral change, not
% just an analysis-output change. Used only by
% run_model_earthquake_floorspace.m. Requires Build_Data col(25)
% (floorspace) to already be populated before this is called.

%% sum floorspace of service buildings in Dm (Dm=Build_Distance_matrix)
[locA,locB]=ismember(Build_Distance_matrix,Build_Data(:,1)); % match building ID
usage_n=zeros(size(locB)); % usage code per neighbor slot
usage_n(locA)=Build_Data(locB(locB>0),3); % copy usage value
usage_n(Build_Distance_matrix==0 | isnan(Build_Distance_matrix))=nan; % NaN for 0 or <radius

floor_n=zeros(size(locB)); % floorspace per neighbor slot
floor_n(locA)=Build_Data(locB(locB>0),25); % copy floorspace value
floor_n(Build_Distance_matrix==0 | isnan(Build_Distance_matrix))=nan;

is_service = usage_n(:,2:end)>1 & usage_n(:,2:end)<4; % combined and commercial buildings
is_residence = usage_n(:,2:end)==1; % living buildings

sum_service_floorspace = nansum(floor_n(:,2:end).*is_service, 2); % commercial floorspace within radius
sum_residence_floorspace = nansum(floor_n(:,2:end).*is_residence, 2); % residential floorspace within radius

Z = sum_residence_floorspace==0; % no residential floorspace within radius at all
service_ratio = zeros(size(Build_Data,1),1);

% Z fallback: no direct floorspace-equivalent of the original count-based
% "/10" constant exists, since floorspace and building-count are
% different units. Normalizes against the average usage==1 building's
% own floorspace instead, so the fallback stays roughly comparable in
% scale to the main (non-Z) branch rather than using a raw floorspace sum
% divided by a bare count-scaled constant. Judgment call -- Z is expected
% to be a rare edge case (a building with literally no residential
% neighbor within radius at all); revisit if it turns out not to be rare.
mean_res_floorspace = mean(Build_Data(Build_Data(:,3)==1,25));
service_ratio(Z) = sum_service_floorspace(Z)./(10*mean_res_floorspace);
service_ratio(Z==0) = sum_service_floorspace(Z==0)./sum_residence_floorspace(Z==0);
Build_Data(:,19)=service_ratio; % append col(19)
Build_Data_p=[Build_Data_p,'service ratio (floorspace-weighted)'];
end
