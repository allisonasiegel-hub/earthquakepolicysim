function [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change,n_accepted]...
    =find_new_house_sa_score(pd,wservice,service_mean,service_std,stat_data,HH_data,Individuals_data,Build_Data...
    ,Build_Distance_matrix_400,Assets,wresd,FFF1,possible_assets)

lu=[];
new_b=[];
hh_change=[];
new_a=[];
n_accepted=0;

%% HH pref
[pref]=pref_hh(pd,wresd,wservice,service_mean,service_std,Build_Data,Build_Distance_matrix_400,Assets,Individuals_data,HH_data,FFF1,stat_data);

SA=HH_data(FFF1,1);

if size(possible_assets,1)>0
    u_sa=unique(possible_assets(:,1)); % unique SA IDs in the candidate pool
    score=[];
    for k=1:size(u_sa,1)
        score(k)=SA_score_old(pd,wresd,wservice,service_mean,service_std,Build_Data,Individuals_data,HH_data,FFF1,u_sa(k),stat_data);
    end

    U_sa=u_sa(score<pref); % SAs that pass the preference threshold

    if size(U_sa,1)>0
        % filter possible_assets to only those in accepted SAs
        possible_assets_accepted = possible_assets(ismember(possible_assets(:,1), U_sa), :);
        n_accepted = size(possible_assets_accepted, 1);
        if n_accepted > 0
            [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change]=new_house(possible_assets_accepted,Assets,HH_data,Build_Data,FFF1);
            if length(new_a)==4
                new_a(:,2)=2;
            end
        end
    end
end
end
