function building_average_sa = cal_bui_sa_subsidy(Work_places, Build_Data, destroyed_B, subsidy_businesses)
u = unique(Work_places(:,1));
h = Build_Data(ismember(Build_Data(:,1),u),3); % col 3 'Usage'
u2 = u(h==3); % only commercial
if (destroyed_B)
    destroyed_ids = destroyed_B(:,1);
else
    destroyed_ids = 0;
end
building_average_sa = zeros(0,2);
for i = 1:length(u2)
    building_salaries = Work_places(Work_places(:,1) == u2(i), 8); % col 8 'salary'
    if subsidy_businesses==1 && ismember(u2(i), destroyed_ids) && length(building_salaries)>1
        %building_salaries = sort(building_salaries, 'descend');
        %building_salaries = building_salaries(1:ceil(end/2));
        building_salaries = 0; % Set expenses to zero for destroyed buildings
    end
    building_average_sa(i,:) = [u2(i), sum(building_salaries)];
end
end
