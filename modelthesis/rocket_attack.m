function [destroyed_B_P, destroyed_B]=rocket_attack(Build_Data, num_buildings)

unique_stat=unique(Build_Data(:,4)); % statistical area
destroyed_B_P={'building ID','recovery time','size'};
if num_buildings>0
    for i=1:num_buildings
        stat=datasample(unique_stat,1);
        b_data=Build_Data(Build_Data(:,4)==stat,:);	
        if ~isempty(b_data)
            B_DAMAGED=datasample(b_data(:,1),1);
            matching_id=Build_Data(:,1)==B_DAMAGED;
            if ~isempty(B_DAMAGED)
                destroyed_B(i, 1)=B_DAMAGED; % building id
                destroyed_B(i, 2)=0; % reset recovery time
                destroyed_B(i, 3)=Build_Data(matching_id,7)*ceil(Build_Data(matching_id,11)); % building floorspace (area*floors)
            else
            end
        end
    end
else
    destroyed_B=[];
end