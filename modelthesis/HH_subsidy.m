function [HH_data, Individuals_data, HH_subsidy_tracker] = HH_subsidy(...
    HH_data, Individuals_data, HH_destroyed, HH_subsidy_tracker, subsidy_residents, subsidy_amount, subsidy_duration, i)

    % -- Grant subsidy to newly displaced households (policy active) --
    if subsidy_residents == 1 && ~isempty(HH_destroyed)
        % Identify HHs newly eligible for subsidy
        new_subsidy_HHs = setdiff(HH_destroyed, HH_subsidy_tracker(:,1));
        for n = 1:length(new_subsidy_HHs)
            hh_id = new_subsidy_HHs(n);
            % Only grant if HH is present in the city
            if any(HH_data(:,2) == hh_id)
                hh_idx = HH_data(:,2) == hh_id;
                % Add subsidy to HH income (col 6), scaled by HH size (col 3)
                HH_data(hh_idx,6) = HH_data(hh_idx,6) + subsidy_amount * HH_data(hh_idx,3);
                % Add subsidy to all household members (col 3 in Individuals_data is HH ID)
                member_idx = Individuals_data(:,3) == hh_id;
                Individuals_data(member_idx,14) = Individuals_data(member_idx,14) + subsidy_amount;
                % Register HH and start day in the tracker
                HH_subsidy_tracker = [HH_subsidy_tracker; hh_id, i];
            end
        end
    end

    % -- Remove subsidy for expired or departed households --
    if ~isempty(HH_subsidy_tracker)
        to_remove = false(size(HH_subsidy_tracker,1),1); % Preallocate removal flags
        for k = 1:size(HH_subsidy_tracker,1)
            hh_id = HH_subsidy_tracker(k,1);
            start_day = HH_subsidy_tracker(k,2);
            % Determine if subsidy duration expired or HH left the city
            expired = (i - start_day) >= subsidy_duration;
            left_world = ~any(HH_data(:,2) == hh_id);
            if expired || left_world
                % If HH still present, subtract subsidy from HH income and members
                if any(HH_data(:,2) == hh_id)
                    hh_idx = HH_data(:,2) == hh_id;
                    HH_data(hh_idx,6) = HH_data(hh_idx,6) - subsidy_amount * HH_data(hh_idx,3);
                    member_idx = Individuals_data(:,3) == hh_id;
                    Individuals_data(member_idx,14) = Individuals_data(member_idx,14) - subsidy_amount;
                end
                to_remove(k) = true; % Mark for tracker removal
            end
        end
        % Remove all households whose subsidy expired or who left the city
        HH_subsidy_tracker(to_remove,:) = [];
    end

end
