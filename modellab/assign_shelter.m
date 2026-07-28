function [Build_Data, Shelters, Shelter_Assign, Shelter_Building_Routines, Building_routine_id, unsheltered_agents] = assign_shelter( ...
    Build_Data, Individuals_data, HH_destroyed, Shelters, Shelter_Assign, Shelter_Building_Routines, Building_routine_id, i, ...
    agents_per_sqm, public_bldg_usable_fraction, restrict_public_shelters_to_schools, hotel_room_density, agents_per_room)
% Assigns displaced agents to public buildings/schools AND hotels (as
% shelters) after attack - the "immediate" sheltering tier. Both are
% tried as one combined candidate pool (public/school tier first, then
% hotels, by concatenation order - no other priority between them).
%
% Public/school tier capacity: agents_per_sqm * public_bldg_usable_fraction
% * Area * floors. public_bldg_usable_fraction accounts for the fact that
% not all of a building's gross floor area converts to usable shelter
% space (hallways, offices, fixed-furniture rooms, upper floors without
% elevator access, etc.) - agents_per_sqm alone (~5 sqm/person) is a
% reasonable density by Sphere humanitarian standards, but applying it to
% 100% of gross floor area overstates real capacity.
%
% restrict_public_shelters_to_schools (boolean): if true, ONLY usage=8
% (school) buildings are eligible for the public/school tier - usage=5
% (generic public: government, religious institutions, etc.) is excluded
% entirely. If false, both usage=5 and usage=8 are eligible together.
% Lets you compare an "all public buildings" vs. "schools only" shelter
% policy without duplicating this function.
%
% Hotel tier capacity: hotel_room_density * agents_per_room * Area *
% floors - see identify_hotels_TVR.m for how hotel_room_density is
% calibrated per city. Cities with no usage=7/8 buildings tagged simply
% never populate the corresponding pool, so these parameters are harmless
% there regardless of value.
%
% unsheltered_agents (optional output, existing callers requesting fewer
% outputs are unaffected): displaced agents left over once available
% shelter buildings run out - i.e. shelter capacity exhausted.

    if restrict_public_shelters_to_schools
        public_tier_buildings = Build_Data(Build_Data(:,3)==8, :); % schools only
    else
        public_tier_buildings = Build_Data(Build_Data(:,3)==5 | Build_Data(:,3)==8, :); % all public + schools
    end
    hotel_buildings = Build_Data(Build_Data(:,3)==7, :);
    if isempty(Shelters)
        shelter_ids = [];
    else
        shelter_ids = Shelters(:,1);
    end
    available_public = setdiff(public_tier_buildings(:,1), shelter_ids);
    available_hotel = setdiff(hotel_buildings(:,1), shelter_ids);
    available = [available_public; available_hotel];
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
        if Build_Data(row,3) == 7 % hotel - room-density-based capacity
            capacity = floor(hotel_room_density * agents_per_room * Build_Data(row,7) * Build_Data(row,11));
        else % public building or school - generic density, discounted for usable floor area
            capacity = floor(agents_per_sqm * public_bldg_usable_fraction * Build_Data(row,7) * Build_Data(row,11));
        end
        n_assign = min(capacity, length(remaining_agents));
        assigned_agents = remaining_agents(1:n_assign);

        % Mark building as shelter (usage code 99) - record its original
        % usage first so release_shelter.m can revert to the right code
        % (public=5, school=8, or hotel=7), not always public.
        original_usage = Build_Data(row,3);
        Build_Data(row,3) = 99;
        Shelters = [Shelters; b_id, i, 0, original_usage]; % [b_id, start_step, end_step=0, original_usage]
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
    unsheltered_agents = remaining_agents; % leftover once available buildings run out
end
