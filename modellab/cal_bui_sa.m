function building_average_sa=cal_bui_sa(Work_places,Build_Data)
u=unique(Work_places(:,1)); % 'building id'
h=Build_Data(ismember(Build_Data(:,1),u),3); % 'Usage' for all unique buildings
u2=u(h==3); % usage index 3 - commercial 
for i=1:length(u2) 
    % total salary for each workplace    
    % TODO: Add if for workplace subs; order and remove the 2 lowest
    

    building_average_sa(i,:)=[u2(i),sum(Work_places(Work_places(:,1)==u2(i),8))];
    %building_average_sa(i,:)=[u2(i),mean(Work_places(Work_places(:,1)==u2(i),8))]; % old calc
    
end