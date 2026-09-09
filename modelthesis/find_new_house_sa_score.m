function [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change,n_accepted]...
    =find_new_house_sa_score(pd,wservice,wservice_old,service_mean,service_std,stat_data,HH_data,Individuals_data,Build_Data...
    ,Build_Distance_matrix_400,Assets,wresd,FFF1,possible_assets,elderly_search_mode)
% elderly_search_mode (optional, default 0): controls how elderly
% out-of-SA search picks a destination, independent of the within-SA
% svc_filter (that's applied upstream by the caller, before
% possible_assets even reaches this function):
%   0 = legacy/off: standard pref_hh/SA_score_old threshold, all
%       accepted SAs' assets combined into one pool, one plain pick.
%   1 = same as 0 but the final asset pick is weighted toward
%       higher-building-service-ratio candidates for elderly (old-old
%       leans harder than young-old -- see new_house.m).
%   2 = SA-level filter REPLACES the pref_hh/SA_score_old threshold for
%       elderly: only SAs with SA-level service ratio >= the household's
%       current SA qualify (same "hard gate" philosophy as the
%       building-level svc_filter, not a soft preference). One
%       destination SA is then weight-picked among the qualifying set
%       (old-old leans harder), and the asset within that one SA is
%       picked plainly at random (no further building-level bias).
%   3 = the standard pref_hh/SA_score_old threshold still determines
%       which SAs qualify (service-blind when wservice=0), but instead of
%       combining all qualifying SAs into one pool, one destination SA is
%       weight-picked among them by SA-level service ratio (old-old
%       leans harder), then the asset within that one SA is ALSO
%       weight-picked by building-level service ratio.
%   4 = same eligibility + SA pick as mode 3 (standard threshold, then
%       weight-picked destination SA), but the asset within that chosen
%       SA is picked PLAINLY at random -- isolates "does concentrating
%       elderly into better SAs help on its own" from "does the extra
%       building-level bias on top of that matter". Within-SA moves
%       (find_new_house_same_stat's own step, upstream of this function)
%       are unaffected -- weight_within_sa there is elderly_search_mode
%       >=1, so mode 4 still weight-picks the asset for a within-SA move,
%       same as modes 1-3.
%   5 = same eligibility + SA pick as mode 3/4 (standard threshold, then
%       weight-picked destination SA, squared/linear as usual), and the
%       asset within that chosen SA IS weight-picked (like mode 3) but
%       with a stronger exponent (young-old squared, old-old cubed,
%       instead of mode 3's linear/squared) -- tested after mode 3
%       proved to have near-zero success-rate cost, to see if pushing
%       the building-level pull harder (without touching the already-
%       validated SA-level mechanics) can also flip building service
%       ratio above non-elderly's, not just SA service ratio. Within-SA
%       moves get the same stronger exponent (see
%       find_new_house_same_stat.m).
%   6 = same hard SA-level filter as mode 2 (only SAs with SA-level
%       service ratio >= current SA qualify), but the SA choice among
%       the qualifying set is PLAIN random for BOTH age groups -- no
%       weighting at the SA-pick step at all, for anyone. Age-group
%       differentiation happens ONLY at the asset-selection step: young-
%       old picks plainly (effectively unweighted -- see the yo_exponent
%       =0 call below), old-old picks weighted (squared) toward higher
%       building service ratio, both for the within-SA move (see
%       find_new_house_same_stat.m, which also needs svc_filter=1 for
%       the hard building-level floor mode 6 relies on) and for the
%       asset within the plain-picked SA on a between-SA move. Tests
%       whether a hard filter alone (a guaranteed floor, no extra push)
%       is enough for young-old, reserving the "reach for the best"
%       behavior for old-old only.
% Non-elderly households (hh_age_group==0) are never affected by any mode
% -- always the legacy single combined-pool plain pick.

if nargin<15 || isempty(elderly_search_mode); elderly_search_mode=0; end

lu=[];
new_b=[];
hh_change=[];
new_a=[];
n_accepted=0;

ageGroup = hh_age_group(HH_data,FFF1); % 0=non-elderly, 1=young-old, 2=old-old
isElderly = ageGroup>=1;

SA=HH_data(FFF1,1);

if size(possible_assets,1)>0
    if (elderly_search_mode==2 || elderly_search_mode==6) && isElderly
        %% modes 2/6: SA-level hard filter (identical); SA pick and asset weighting differ
        [~,loc_curr_sa] = ismember(SA, stat_data(:,1));
        curr_sa_svc = 0;
        if loc_curr_sa>0
            curr_sa_svc = stat_data(loc_curr_sa,5);
        end

        u_sa=unique(possible_assets(:,1));
        [~,loc_sa] = ismember(u_sa, stat_data(:,1));
        sa_svc = zeros(size(u_sa));
        valid_sa = loc_sa>0;
        sa_svc(valid_sa) = stat_data(loc_sa(valid_sa),5);

        qualifies = sa_svc >= curr_sa_svc;
        U_sa = u_sa(qualifies);
        U_sa_svc = sa_svc(qualifies);

        if size(U_sa,1)>0
            if elderly_search_mode==6
                chosen_sa = datasample(U_sa,1); % plain: no weighting at the SA-pick step for either group
            else
                chosen_sa = pick_weighted_sa(U_sa, U_sa_svc, ageGroup);
            end
            possible_assets_accepted = possible_assets(possible_assets(:,1)==chosen_sa, :);
            n_accepted = size(possible_assets_accepted, 1);
            if n_accepted > 0
                if elderly_search_mode==6
                    % old-old weighted (squared) toward building service ratio; young-old plain (yo_exponent=0 -> uniform weights)
                    [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change]=new_house(possible_assets_accepted,Assets,HH_data,Build_Data,FFF1,true,0,2);
                else
                    [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change]=new_house(possible_assets_accepted,Assets,HH_data,Build_Data,FFF1,false);
                end
                if length(new_a)==4
                    new_a(:,2)=2;
                end
            end
        end
    else
        %% modes 0/1/3: standard preference-threshold eligibility (unchanged)
        [pref]=pref_hh(pd,wresd,wservice,wservice_old,service_mean,service_std,Build_Data,Build_Distance_matrix_400,Assets,Individuals_data,HH_data,FFF1,stat_data);

        u_sa=unique(possible_assets(:,1)); % unique SA IDs in the candidate pool
        score=[];
        for k=1:size(u_sa,1)
            score(k)=SA_score_old(pd,wresd,wservice,wservice_old,service_mean,service_std,Build_Data,Individuals_data,HH_data,FFF1,u_sa(k),stat_data);
        end

        U_sa=u_sa(score<pref); % SAs that pass the preference threshold

        if size(U_sa,1)>0
            if (elderly_search_mode==3 || elderly_search_mode==4 || elderly_search_mode==5) && isElderly
                %% modes 3/4/5: weighted SA pick among the eligible set; asset pick within it differs
                [~,loc_sa] = ismember(U_sa, stat_data(:,1));
                sa_svc = zeros(size(U_sa));
                valid_sa = loc_sa>0;
                sa_svc(valid_sa) = stat_data(loc_sa(valid_sa),5);

                chosen_sa = pick_weighted_sa(U_sa, sa_svc, ageGroup);
                possible_assets_accepted = possible_assets(possible_assets(:,1)==chosen_sa, :);
                n_accepted = size(possible_assets_accepted, 1);
                if n_accepted > 0
                    weight_asset = (elderly_search_mode==3 || elderly_search_mode==5); % mode3/5: also weight the asset pick; mode4: plain pick
                    if elderly_search_mode==5
                        [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change]=new_house(possible_assets_accepted,Assets,HH_data,Build_Data,FFF1,weight_asset,2,3);
                    else
                        [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change]=new_house(possible_assets_accepted,Assets,HH_data,Build_Data,FFF1,weight_asset);
                    end
                    if length(new_a)==4
                        new_a(:,2)=2;
                    end
                end
            else
                %% modes 0/1: combine all accepted SAs, one pick (weighted for mode 1 elderly)
                possible_assets_accepted = possible_assets(ismember(possible_assets(:,1), U_sa), :);
                n_accepted = size(possible_assets_accepted, 1);
                if n_accepted > 0
                    weight_this = (elderly_search_mode==1 && isElderly);
                    [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change]=new_house(possible_assets_accepted,Assets,HH_data,Build_Data,FFF1,weight_this);
                    if length(new_a)==4
                        new_a(:,2)=2;
                    end
                end
            end
        end
    end
end
end


function chosen_sa = pick_weighted_sa(sa_ids, sa_svc, ageGroup)
% Weight-pick one SA from sa_ids by sa_svc (SA-level service ratio),
% old-old (ageGroup==2) leaning harder toward the top (svc^2) than
% young-old (svc^1) -- same rationale as new_house.m's asset-level pick.
if size(sa_ids,1)>1
    base_w = sa_svc - min(sa_svc) + eps;
    if ageGroup==2
        w = base_w.^2;
    else
        w = base_w;
    end
    idx = datasample(1:size(sa_ids,1), 1, 'Weights', w);
    chosen_sa = sa_ids(idx);
else
    chosen_sa = sa_ids(1);
end
end
