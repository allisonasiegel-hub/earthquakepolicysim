function Build_Distance_matrix=building_within_D(Build_Data,D)
S=size(Build_Data,1);
% create empty matrix
Build_Distance_matrix=nan(S,50);
% loop running on all buildings
for i=1:S
    % find building id and xy
    id=Build_Data(i,1);
    xy=Build_Data(i,5:6);
    % cal dis between the build and all other
    dis=sqrt((xy(:,1)-Build_Data(:,5)).^2+(xy(:,2)-Build_Data(:,6)).^2);
    % find where dis <input
    dis=(dis<=D) & (dis~=0); %not same building and within the distance
    % create row with the building id and all ids of buildings in the wanted distance
    Build_Distance_matrix(i,1)=id;
    Build_Distance_matrix(i,2:sum(dis)+1)=Build_Data(dis,1);
end
Build_Distance_matrix(Build_Distance_matrix==0)=nan;