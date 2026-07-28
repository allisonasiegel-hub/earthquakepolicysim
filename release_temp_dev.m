function [Temp_Dev_Assign, released_agents] = release_temp_dev(Individuals_data, HH_data, Assets, recovered_bldgs, Temp_Dev_Assign)
% Releases agents from a medium-term temp-dev site once their household
% secures a new asset or their original home building recovers - same
% exit conditions as release_shelter.m. There's no Build_Data usage to
% revert here: temp-dev sites are abstract bookkeeping (Temp_Dev_Sites/
% Temp_Dev_Assign), never a real building - see site_temp_dev_locations.m.

    released_agents = [];
    if isempty(Temp_Dev_Assign)
        return
    end

    assigned_agents = Temp_Dev_Assign(:,1);
    for a = 1:length(assigned_agents)
        agent_row = find(Individuals_data(:,1)==assigned_agents(a), 1);
        if isempty(agent_row)
            released_agents = [released_agents; assigned_agents(a)]; % agent no longer exists - clean up bookkeeping
            continue
        end
        agent_hh = Individuals_data(agent_row,3);
        hh_row = find(HH_data(:,2)==agent_hh, 1);
        if isempty(hh_row)
            continue
        end
        agent_bldg   = HH_data(hh_row,10);
        asset_id     = HH_data(hh_row,11);
        asset_in_use = ismember(asset_id, Assets(:,3));
        if ismember(agent_bldg, recovered_bldgs) || asset_in_use
            released_agents = [released_agents; assigned_agents(a)];
        end
    end
    Temp_Dev_Assign = Temp_Dev_Assign(~ismember(Temp_Dev_Assign(:,1), released_agents), :);
end
