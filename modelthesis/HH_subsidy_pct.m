function [HH_data, HH_subsidy_tracker] = HH_subsidy_pct(...
    HH_data, HH_destroyed, HH_subsidy_tracker, subsidy_residents, subsidy_pct, w_subsidy_eld, subsidy_duration, i)
% Housing subsidy as a percent of household income, frozen at the income
% level on the step the household is granted the subsidy (shock step),
% with a higher percent for elderly households (HH_data col 5 >= 2).
% Added to HH income only (HH_data col 6) - never touches individual
% wages (Individuals_data), so it stays out of labor-market / business
% submodel dynamics (average_wage, building salary rankings, etc).
%
% subsidy_pct      = base fraction of frozen income granted (e.g. 0.15)
% w_subsidy_eld    = elderly premium weight; elderly households get
%                    subsidy_pct*(1+w_subsidy_eld) of their income instead
%                    of just subsidy_pct
%
% HH_subsidy_tracker columns: [HH_ID, start_step, granted_amount]
% granted_amount is the actual shekel amount added at grant time, stored
% so it can be subtracted EXACTLY at expiry - recomputing
% "subsidy_pct * current income" at removal time would be wrong, since
% income may have drifted (wage dynamics) or already include the subsidy.

    % -- Grant subsidy to newly displaced households (policy active) --
    if subsidy_residents == 1 && ~isempty(HH_destroyed)
        new_subsidy_HHs = setdiff(HH_destroyed, HH_subsidy_tracker(:,1));
        for n = 1:length(new_subsidy_HHs)
            hh_id = new_subsidy_HHs(n);
            if any(HH_data(:,2) == hh_id)
                hh_idx = HH_data(:,2) == hh_id;
                isEld = HH_data(hh_idx,5) >= 2;
                pct = subsidy_pct * (1 + w_subsidy_eld * isEld);
                granted = pct * HH_data(hh_idx,6); % % of income frozen at grant time
                HH_data(hh_idx,6) = HH_data(hh_idx,6) + granted;
                HH_subsidy_tracker = [HH_subsidy_tracker; hh_id, i, granted];
            end
        end
    end

    % -- Remove subsidy for expired or departed households --
    if ~isempty(HH_subsidy_tracker)
        to_remove = false(size(HH_subsidy_tracker,1),1);
        for k = 1:size(HH_subsidy_tracker,1)
            hh_id      = HH_subsidy_tracker(k,1);
            start_day  = HH_subsidy_tracker(k,2);
            granted    = HH_subsidy_tracker(k,3);
            expired    = (i - start_day) >= subsidy_duration;
            left_world = ~any(HH_data(:,2) == hh_id);
            if expired || left_world
                if any(HH_data(:,2) == hh_id)
                    hh_idx = HH_data(:,2) == hh_id;
                    HH_data(hh_idx,6) = HH_data(hh_idx,6) - granted;
                end
                to_remove(k) = true;
            end
        end
        HH_subsidy_tracker(to_remove,:) = [];
    end
end
