function [Build_Data, Shelters, Shelter_Assign, Shelter_Building_Routines, Building_routine_id, released_agents] = release_shelter( ...
    Build_Data, Individuals_data, HH_data, Shelters, Shelter_Assign, Shelter_Building_Routines, Building_routine_id, Assets, recovered_bldgs, i)
% Releases agents from shelter after home recovery or when new assets become
% available. Agents are also released once their household secures any asset
% from the available list. Shelters are closed if no agents remain.
%
% released_agents: every agent ID released this call, across all shelter
% buildings - for the caller to trigger a routine recompute back onto
% their (now-correct) HH_data home.
    released_agents = [];
    for sidx = size(Shelters,1):-1:1
        b_id = Shelters(sidx,1);

        % Remove assignments of agents no longer in the population
        assigned_agents = Shelter_Assign(Shelter_Assign(:,2)==b_id,1);
        keep_mask = ismember(assigned_agents, Individuals_data(:,1));
        if any(~keep_mask)
            stale_agents = assigned_agents(~keep_mask);
            for sa = 1:length(stale_agents)
                idx = (Shelter_Assign(:,1)==stale_agents(sa)) & (Shelter_Assign(:,2)==b_id);
                Shelter_Assign(idx,:) = [];
            end
        end

        % Updated list after removing stale entries
        assigned_agents = Shelter_Assign(Shelter_Assign(:,2)==b_id,1);
        agents_to_release = [];
        for a = 1:length(assigned_agents)
            agent_row = find(Individuals_data(:,1)==assigned_agents(a), 1);
            if ~isempty(agent_row)
                agent_hh = Individuals_data(agent_row,3); % scalar
                hh_row = find(HH_data(:,2)==agent_hh, 1);
                if ~isempty(hh_row)
                    agent_bldg  = HH_data(hh_row,10);
                    asset_id    = HH_data(hh_row,11);

                    asset_in_use = ismember(asset_id, Assets(:,3));
                    if ismember(agent_bldg, recovered_bldgs) || asset_in_use
                        agents_to_release = [agents_to_release; assigned_agents(a)];
                    end
                end
            end
        end
        released_agents = [released_agents; agents_to_release];
        % Remove released agents from assignment
        for r = 1:length(agents_to_release)
            idx = (Shelter_Assign(:,1)==agents_to_release(r)) & (Shelter_Assign(:,2)==b_id);
            Shelter_Assign(idx,:) = [];
        end
        still_assigned = Shelter_Assign(Shelter_Assign(:,2)==b_id,1);
        if isempty(still_assigned)
            Build_Data(Build_Data(:,1)==b_id,3) = Shelters(sidx,4); % revert to its original usage (not always public)
            Shelters(sidx,3) = i; % end step
            % Optional: Restore building in routines
            k = [];
            if ~isempty(Shelter_Building_Routines)
                k = find([Shelter_Building_Routines{:,1}] == b_id, 1);
            end
            if ~isempty(k)
                orig_rows = Shelter_Building_Routines{k,2};
                for m = 1:size(orig_rows,1)
                    aid = orig_rows(m,1);
                    arow = find(Building_routine_id(:,1)==aid);
                    if ~isempty(arow)
                        Building_routine_id(arow,:) = orig_rows(m,:);
                    end
                end
                Shelter_Building_Routines(k,:) = [];
            end
            Shelters(sidx,:) = [];
        end
    end
end
