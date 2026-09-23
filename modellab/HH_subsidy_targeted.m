function [HH_data, Individuals_data, HH_subsidy_tracker, n_hh_subsidized_total, total_aid_distributed] = HH_subsidy_targeted(...
    HH_data, Individuals_data, HH_destroyed, HH_subsidy_tracker, Assets, bad_Assets, ...
    Shelter_Assign, Sheltered_Outside, Temp_Dev_Assign, ...
    subsidy_residents_mode, subsidy_duration, i, n_hh_subsidized_total, total_aid_distributed)
% n_hh_subsidized_total/total_aid_distributed: pass-through accumulators
% (same threading pattern as HH_subsidy_tracker - init to 0 once outside
% the step loop, fed back in and out every call) for sweep-analysis
% outputs (chat 2026-09-15):
%   n_hh_subsidized_total - cumulative count of DISTINCT households ever
%     granted this subsidy (incremented once per household, the step it
%     first becomes eligible - not re-counted on later steps).
%   total_aid_distributed - cumulative dollars actually paid out over the
%     whole run. The subsidy is added to a household's ONGOING income
%     (HH_data col 6), not a one-time lump sum, so a household collects
%     it every week it's active - this sums each recipient's amount
%     across every step it's still active AFTER that step's grants AND
%     removals both apply, so a household expiring this exact step is
%     correctly paid for exactly its own duration, not one week too many.
% Targeted household subsidy for run_model_earthquake_shelteroverflow.m.
% Kept separate from the shared HH_subsidy.m (used unmodified by
% run_model_eq.m, run_model_earthquake.m, diag_*.m) since this variant
% changes both the eligibility rule and the amount formula - see chat
% 2026-09-15/17. Modes 1-4 (removed 2026-09-18) were early, since-
% superseded designs; only 0/5/6 remain.
%
% subsidy_residents_mode:
%   0 = off
%   5 = displaced households only (HH_destroyed at the shock). Amount:
%       tiered by the household's OWN income decile (HH_data col 7) -
%       decile 7-10 gets 30% of housing cost, decile 4-6 gets 35%, decile
%       1-3 gets 40% (lower income -> higher percentage). Fixed 4-step
%       duration, NOT subsidy_duration - a deliberately shorter, one-time-
%       feeling payment (chat 2026-09-17). No early exit.
%   6 = displaced households only (same eligibility as mode 5). Amount:
%       same decile-tier idea as mode 5, but smaller percentages and a
%       longer window - decile 7-10 gets 10%, decile 4-6 gets 15%, decile
%       1-3 gets 20%. Fixed 12-step (3-month) duration, NOT
%       subsidy_duration - was 8 steps until chat 2026-09-20, extended to
%       match a 3-month policy target. No early exit.
% Modes 5/6 use FIXED durations (4 and 12 steps respectively) regardless
% of whatever subsidy_duration is set to.
%
% Housing-cost lookup: Assets/bad_Assets col 13 ("cost of life" - see
% monthly_ass_cost.m). A displaced household's cost is read from
% bad_Assets (their now-destroyed home - HH_data col 11 still points at
% that asset id until the household is reassigned, see new_house.m).
%
% HH_subsidy_tracker columns: [HH_ID, subsidy_start_step, subsidy_amount,
% was_displaced_at_grant] - subsidy_amount is the FULL per-household
% amount (already summed across members, matches how it's added to
% HH_data col 6 below). was_displaced_at_grant is always 1 for modes 5/6
% (displaced-only); the column is kept for tracker-format stability.
%
% WAGE-YARDSTICK FIX REVERTED (chat 2026-09-22, on request): the
% 2026-09-20 fix that added the subsidy ONLY to HH_data col 6, not to
% Individuals_data col 14, has been undone - every household member's
% individual income is bumped by the same subsidy_amount again, matching
% the original shared HH_subsidy.m (rocketattack/RABM-matlab) pattern.
% This does feed subsidized income into average_wage/std_wage
% (recomputed every step from col 14 in
% run_model_earthquake_shelteroverflow.m), the same city-wide yardstick
% the land-use job-creation ranking uses - see the fix's own writeup
% (git history / chat 2026-09-20) for what that distorts. Deliberately
% restored anyway per chat 2026-09-22.

    if subsidy_residents_mode > 0 && subsidy_residents_mode ~= 5 && subsidy_residents_mode ~= 6
        error('HH_subsidy_targeted:invalidMode', ...
            'subsidy_residents_mode=%d is not supported - modes 1-4 were removed 2026-09-18, only 0 (off), 5, and 6 remain.', ...
            subsidy_residents_mode);
    end

    if subsidy_residents_mode > 0
        newly_destroyed = setdiff(HH_destroyed, HH_subsidy_tracker(:,1));
        newly_eligible = newly_destroyed;

        for n = 1:length(newly_eligible)
            hh_id = newly_eligible(n);
            hh_idx = HH_data(:,2) == hh_id;
            if ~any(hh_idx)
                continue
            end
            hh_row = find(hh_idx, 1);
            is_displaced = ismember(hh_id, newly_destroyed);

            % Decile-tiered percentage of housing cost, read from
            % bad_Assets (displaced-only, see header comment).
            decile = HH_data(hh_row, 7);
            if subsidy_residents_mode == 5
                fraction = decile_tier_fraction(decile, 0.30, 0.35, 0.40);
            else
                fraction = decile_tier_fraction(decile, 0.10, 0.15, 0.20);
            end
            asset_id = HH_data(hh_row, 11);
            cost_row = find(bad_Assets(:,3) == asset_id, 1);
            housing_cost = 0;
            if ~isempty(cost_row)
                housing_cost = bad_Assets(cost_row, 13);
            end
            if isnan(housing_cost)
                housing_cost = 0;
            end
            subsidy_amount = fraction * housing_cost;
            if isnan(subsidy_amount)
                subsidy_amount = 0;
            end

            HH_data(hh_idx, 6) = HH_data(hh_idx, 6) + subsidy_amount;
            member_idx = Individuals_data(:,3) == hh_id;
            Individuals_data(member_idx, 14) = Individuals_data(member_idx, 14) + subsidy_amount;

            HH_subsidy_tracker = [HH_subsidy_tracker; hh_id, i, subsidy_amount, double(is_displaced)];
            n_hh_subsidized_total = n_hh_subsidized_total + 1;
        end
    end

    % -- Remove subsidy for expired or departed households --
    if ~isempty(HH_subsidy_tracker)
        % Modes 5/6 use their own fixed duration, not the externally-
        % configurable subsidy_duration - see this function's header.
        effective_duration = subsidy_duration;
        if subsidy_residents_mode == 5
            effective_duration = 4;
        elseif subsidy_residents_mode == 6
            effective_duration = 12;
        end

        to_remove = false(size(HH_subsidy_tracker,1),1);
        for k = 1:size(HH_subsidy_tracker,1)
            hh_id = HH_subsidy_tracker(k,1);
            start_step = HH_subsidy_tracker(k,2);
            subsidy_amount = HH_subsidy_tracker(k,3);
            expired = (i - start_step) >= effective_duration;
            hh_idx = HH_data(:,2) == hh_id;
            left_world = ~any(hh_idx);
            if expired || left_world
                if any(hh_idx)
                    HH_data(hh_idx, 6) = HH_data(hh_idx, 6) - subsidy_amount;
                    member_idx = Individuals_data(:,3) == hh_id;
                    Individuals_data(member_idx, 14) = Individuals_data(member_idx, 14) - subsidy_amount;
                end
                to_remove(k) = true;
            end
        end
        HH_subsidy_tracker(to_remove,:) = [];
    end

    % Accumulate AFTER removal, not before: a household stopping THIS
    % step (expiry, resettlement, or departure) must NOT be counted for
    % this step too - see chat 2026-09-15 (unit test caught this
    % double-count when accumulation was placed before removal).
    if ~isempty(HH_subsidy_tracker)
        total_aid_distributed = total_aid_distributed + sum(HH_subsidy_tracker(:,3));
    end

end

function frac = decile_tier_fraction(decile, top_frac, mid_frac, low_frac)
% Modes 5/6's decile-tier lookup: 7-10 = top, 4-6 = middle, 1-3 = low.
    if ismember(decile, [7, 8, 9, 10])
        frac = top_frac;
    elseif ismember(decile, [4, 5, 6])
        frac = mid_frac;
    else
        frac = low_frac;
    end
end
