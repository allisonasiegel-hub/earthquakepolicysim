function [HH_ID,HH_data,Assets,HH_change,LU,new_A,new_B,Build_Data,Asset_Avail]...
    =find_new_house_same_stat(HH_ID,pd,wservice,service_mean,service_std,stat_data,HH_data,Individuals_data,Build_Data,...
    Build_Distance_matrix_400,Assets,wresd,FFF1,LU,new_A,new_B,HH_change,Asset_Avail,svc_filter)

for j=1:size(FFF1,1)
    lu=[];
    new_b=[];
    hh_change=[];
    new_a=[];
    n_accepted_Y=0;
    n_accepted_O=0;
    success_SA=0;
    success_city=0;

    FFF=find(HH_data(:,2)==FFF1(j));
    SA=HH_data(FFF,1);
    income=HH_data(FFF,6);
    Yeshuv=HH_data(FFF,9);
    IX=1;

    possible_assets  =Assets(Assets(:,1)==SA & Assets(:,11)==0 & Assets(:,13)<=0.33*income,:);
    possible_assets_Y=Assets(Assets(:,1)~=SA & Assets(:,6)==Yeshuv & Assets(:,11)==0 & Assets(:,13)<=IX*income,:);
    possible_assets_O=Assets(Assets(:,1)~=SA & Assets(:,6)~=Yeshuv & Assets(:,11)==0 & Assets(:,13)<=IX*income,:);

    isElderly = HH_data(FFF,5)>=2;

    % for elderly: filter within-SA pool to buildings with service ratio >= current building
    if isElderly && svc_filter==1 && size(possible_assets,1)>0
        curr_build_id = HH_data(FFF,10);
        loc_curr = find(Build_Data(:,1)==curr_build_id, 1);
        if ~isempty(loc_curr)
            curr_svc = Build_Data(loc_curr, 19);
        else
            curr_svc = 0;
        end
        [~,locB] = ismember(possible_assets(:,2), Build_Data(:,1));
        valid = locB>0;
        asset_svc = zeros(size(possible_assets,1),1);
        asset_svc(valid) = Build_Data(locB(valid), 19);
        possible_assets = possible_assets(asset_svc >= curr_svc, :);
    end

    n_SA   = size(possible_assets,1);
    tried_SA   = 1;
    tried_city = 0;

    if size(possible_assets,1)>0
        [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change]=new_house(possible_assets,Assets,HH_data,Build_Data,FFF);
        success_SA = double(~isempty(hh_change));
    elseif size(possible_assets_Y,1)>0
        tried_city = 1;
        [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change,n_accepted_Y]=find_new_house_sa_score(...
            pd,wservice,service_mean,service_std,stat_data,HH_data,Individuals_data,Build_Data,...
            Build_Distance_matrix_400,Assets,wresd,FFF,possible_assets_Y);
        success_city = double(~isempty(hh_change));
    end

    if isempty(new_a)
        tried_city = 1;
        [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change,n_accepted_O]=find_new_house_sa_score(...
            pd,wservice,service_mean,service_std,stat_data,HH_data,Individuals_data,Build_Data,...
            Build_Distance_matrix_400,Assets,wresd,FFF,possible_assets_O);
        if length(new_a)==4
            new_a(:,2)=3;
        end
        if ~isempty(hh_change); success_city=1; end
    end

    n_city = n_accepted_Y + n_accepted_O;

    % Asset_Avail: [HH_ID, isElderly, n_SA_assets, n_city_assets, tried_SA, tried_city, success_SA, success_city]
    Asset_Avail=[Asset_Avail; HH_data(FFF,2), double(isElderly), n_SA, n_city, tried_SA, tried_city, success_SA, success_city];

    if isempty(new_a)
        HH_ID=[HH_ID;FFF1(j)];
    end
    LU=[LU;lu];
    new_A=[new_A;new_a];
    new_B=[new_B;new_b];
    HH_change=[HH_change;hh_change];
end
