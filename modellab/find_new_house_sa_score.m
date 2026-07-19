function [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change]...
    =find_new_house_sa_score(pd,HH_data,Individuals_data,Build_Data...
    ,Build_Distance_matrix_400,Assets,wresd,FFF1,possible_assets)


lu=[];
new_b=[];
hh_change=[];
new_a=[];
%% HH pref
[pref]=pref_hh(pd,wresd,Build_Data,Build_Distance_matrix_400,Assets,Individuals_data,HH_data,FFF1);
% HH data
income=HH_data(FFF1,6); % all HH income
SA=HH_data(FFF1,1); % stat


if size(possible_assets,1)>0
    u_sa=unique(possible_assets(:,1)); % unique SA for assets
    score=[];
    for k=1:size(u_sa,1)
        score(k)=SA_score_old(pd,wresd,Build_Data,Individuals_data,HH_data,FFF1,u_sa(k));
        % same calculations as pref_hh
    end
    
    U_sa=u_sa(score<pref); % SAs that pass the preference threshold
    if size(U_sa,1)>0
        % filter possible_assets to only those in accepted SAs (bug fix:
        % U_sa was previously computed but never applied here, so every
        % asset in the original pool was considered regardless of SA score)
        possible_assets_accepted = possible_assets(ismember(possible_assets(:,1), U_sa), :);
        if size(possible_assets_accepted,1)>0
            [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change]=new_house(possible_assets_accepted,Assets,HH_data,Build_Data,FFF1);
            if length(new_a)==4
                new_a(:,2)=2;
            end
        end
    end
end
end
