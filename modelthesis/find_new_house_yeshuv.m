function [HH_ID,HH_data,Assets,HH_change,LU,new_A,new_B,Build_Data,Asset_Avail]...
    =find_new_house_yeshuv(HH_ID,pd,wservice,wservice_old,service_mean,service_std,stat_data,HH_data,Individuals_data,Build_Data...
    ,Build_Distance_matrix_400,Assets,wresd,FFF1,LU,new_A,new_B,HH_change,Asset_Avail)

for j=1:size(FFF1,1)
    lu=[];
    new_b=[];
    hh_change=[];
    new_a=[];
    n_accepted_Y=0;
    n_accepted_O=0;
    success_city=0;

    FFF=find(HH_data(:,2)==FFF1(j));
    SA=HH_data(FFF,1);
    income=HH_data(FFF,6);
    Yeshuv=HH_data(FFF,9);
    IX=1;

    possible_assets_Y=Assets(Assets(:,1)~=SA & Assets(:,6)==Yeshuv & Assets(:,11)==0 & Assets(:,13)<=IX*income,:);
    possible_assets_O=Assets(Assets(:,1)~=SA & Assets(:,6)~=Yeshuv & Assets(:,11)==0 & Assets(:,13)<=IX*income,:);

    % Only assets in buildings still zoned residential can be reoccupied
    % (see filter_residential_assets.m).
    possible_assets_Y = filter_residential_assets(possible_assets_Y, Build_Data);
    possible_assets_O = filter_residential_assets(possible_assets_O, Build_Data);

    ageGroup = HH_data(FFF,5); % 0=non-elderly, 3=young-old, 6=old-old

    if size(possible_assets_Y,1)>0
        [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change,n_accepted_Y]=find_new_house_sa_score(...
            pd,wservice,wservice_old,service_mean,service_std,stat_data,HH_data,Individuals_data,...
            Build_Data,Build_Distance_matrix_400,Assets,wresd,FFF,possible_assets_Y);
        if ~isempty(hh_change); success_city=1; end
    end

    if isempty(new_a) && size(possible_assets_O,1)>0
        [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change,n_accepted_O]=find_new_house_sa_score(...
            pd,wservice,wservice_old,service_mean,service_std,stat_data,HH_data,Individuals_data,...
            Build_Data,Build_Distance_matrix_400,Assets,wresd,FFF,possible_assets_O);
        if length(new_a)==4
            new_a(:,2)=3;
        end
        if ~isempty(hh_change); success_city=1; end
    end

    n_city = n_accepted_Y + n_accepted_O;

    % Asset_Avail: [HH_ID, ageGroup(0=non-elderly,3=young-old,6=old-old), n_SA_assets, n_city_assets, tried_SA, tried_city, success_SA, success_city]
    Asset_Avail=[Asset_Avail; HH_data(FFF,2), ageGroup, 0, n_city, 0, 1, 0, success_city];

    if isempty(new_a)
        HH_ID=[HH_ID;FFF1(j)];
    end
    LU=[LU;lu];
    new_A=[new_A;new_a];
    new_B=[new_B;new_b];
    HH_change=[HH_change;hh_change];
end
