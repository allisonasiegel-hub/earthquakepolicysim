function [Build_Data, Shelters, Shelter_Assign, Shelter_Building_Routines, Building_routine_id] = assign_shelter( ...
    Build_Data, Individuals_data, HH_destroyed, Shelters, Shelter_Assign, Shelter_Building_Routines, Building_routine_id, i, agents_per_sqm)
% Assigns displaced agents to public buildings (as shelters) after attack

    public_buildings = Build_Data(Build_Data(:,3)==5, :);
    if isempty(Shelters)
        shelter_ids = [];
    else
        shelter_ids = Shelters(:,1);
    end
    available = setdiff(public_buildings(:,1), shelter_ids);
    % Get list of all displaced agent IDs
    displaced_agents = [];
    for hidx = 1:length(HH_destroyed)
        agent_ids = Individuals_data(Individuals_data(:,3)==HH_destroyed(hidx),1);
        displaced_agents = [displaced_agents; agent_ids];
    end
    remaining_agents = displaced_agents;
    next_shelter = 1;
    while ~isempty(remaining_agents) && next_shelter <= length(available)
        b_id = available(next_shelter);
        row = Build_Data(:,1) == b_id;
        capacity = floor(agents_per_sqm * Build_Data(row,7) * Build_Data(row,11));
        n_assign = min(capacity, length(remaining_agents));
        assigned_agents = remaining_agents(1:n_assign);

        % Mark building as shelter (usage code 99)
        Build_Data(row,3) = 99;
        Shelters = [Shelters; b_id, i, 0]; % [b_id, start_step, end_step=0]
        Shelter_Assign = [Shelter_Assign; [assigned_agents, repmat(b_id, n_assign, 1)]];
        
        % Optional: Remove shelter from routines of all agents visiting it
        agents_with_b = find(any(Building_routine_id(:,2:end)==b_id,2));
        Shelter_Building_Routines{end+1,1} = b_id;
        Shelter_Building_Routines{end,2} = Building_routine_id(agents_with_b,:);
        for aidx = agents_with_b'
            br = Building_routine_id(aidx,:);
            br(br==b_id) = NaN; % remove building from routine
            Building_routine_id(aidx,:) = br;
        end
        
        remaining_agents(1:n_assign) = [];
        next_shelter = next_shelter + 1;
    end
end