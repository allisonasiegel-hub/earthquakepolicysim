function [HH_ID,HH_data,Assets,HH_change,LU,new_A,new_B,Build_Data,Asset_Avail]...
    =find_new_house_same_stat(HH_ID,pd,wservice,wservice_old,service_mean,service_std,stat_data,HH_data,Individuals_data,Build_Data,...
    Build_Distance_matrix_400,Assets,wresd,FFF1,LU,new_A,new_B,HH_change,Asset_Avail,svc_filter,elderly_search_mode)
% svc_filter: within-SA building-level service-ratio filter, unchanged
% from before -- mode 6 relies on this being 1 for its "hard floor"
% design (see find_new_house_sa_score.m's header). elderly_search_mode
% (optional, default 0): see find_new_house_sa_score.m's header for the
% full mode definitions -- mode 1 additionally extends svc_filter's
% building-level filter to the out-of-SA pools too; modes 2/3/4/5/6
% handle out-of-SA search their own way inside find_new_house_sa_score.m
% instead. Mode 5 uses a stronger exponent (young-old squared, old-old
% cubed) for the within-SA weighted asset pick below, matching its
% out-of-SA behavior; mode 6 uses yo_exponent=0 (plain/uniform for
% young-old) and oo_exponent=2 (squared for old-old), also matching its
% out-of-SA behavior.
if nargin<21 || isempty(elderly_search_mode); elderly_search_mode=0; end

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

    % Only assets in buildings still zoned residential (usage 1 or 2,
    % matching SA_RESIDENT's own definition) are habitable -- a building
    % converted to commercial via land-use change can't be reoccupied
    % until it converts back.
    possible_assets   = filter_residential_assets(possible_assets,   Build_Data);
    possible_assets_Y = filter_residential_assets(possible_assets_Y, Build_Data);
    possible_assets_O = filter_residential_assets(possible_assets_O, Build_Data);

    ageGroup = HH_data(FFF,5); % 0=non-elderly, 3=young-old, 6=old-old
    isElderly = ageGroup>=2;

    % for elderly: filter the within-SA pool to buildings with service
    % ratio >= current building. Out-of-SA pools ALSO get this same
    % building-level filter only in mode 1 (mode 2 uses an SA-level
    % filter instead, inside find_new_house_sa_score.m; mode 3 uses no
    % filter at all out-of-SA either).
    if isElderly && svc_filter==1
        curr_build_id = HH_data(FFF,10);
        loc_curr = find(Build_Data(:,1)==curr_build_id, 1);
        if ~isempty(loc_curr)
            curr_svc = Build_Data(loc_curr, 19);
        else
            curr_svc = 0;
        end
        possible_assets = filter_by_building_service(possible_assets, Build_Data, curr_svc);
        if elderly_search_mode==1
            possible_assets_Y = filter_by_building_service(possible_assets_Y, Build_Data, curr_svc);
            possible_assets_O = filter_by_building_service(possible_assets_O, Build_Data, curr_svc);
        end
    end

    n_SA   = size(possible_assets,1);
    tried_SA   = 1;
    tried_city = 0;
    weight_within_sa = isElderly && elderly_search_mode>=1;

    if size(possible_assets,1)>0
        if elderly_search_mode==5
            [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change]=new_house(possible_assets,Assets,HH_data,Build_Data,FFF,weight_within_sa,2,3);
        elseif elderly_search_mode==6
            % old-old weighted (squared), young-old plain (yo_exponent=0 -> uniform weights)
            [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change]=new_house(possible_assets,Assets,HH_data,Build_Data,FFF,weight_within_sa,0,2);
        else
            [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change]=new_house(possible_assets,Assets,HH_data,Build_Data,FFF,weight_within_sa);
        end
        success_SA = double(~isempty(hh_change));
    elseif size(possible_assets_Y,1)>0
        tried_city = 1;
        [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change,n_accepted_Y]=find_new_house_sa_score(...
            pd,wservice,wservice_old,service_mean,service_std,stat_data,HH_data,Individuals_data,Build_Data,...
            Build_Distance_matrix_400,Assets,wresd,FFF,possible_assets_Y,elderly_search_mode);
        success_city = double(~isempty(hh_change));
    end

    if isempty(new_a)
        tried_city = 1;
        [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change,n_accepted_O]=find_new_house_sa_score(...
            pd,wservice,wservice_old,service_mean,service_std,stat_data,HH_data,Individuals_data,Build_Data,...
            Build_Distance_matrix_400,Assets,wresd,FFF,possible_assets_O,elderly_search_mode);
        if length(new_a)==4
            new_a(:,2)=3;
        end
        if ~isempty(hh_change); success_city=1; end
    end

    n_city = n_accepted_Y + n_accepted_O;

    % Asset_Avail: [HH_ID, ageGroup(0=non-elderly,3=young-old,6=old-old), n_SA_assets, n_city_assets, tried_SA, tried_city, success_SA, success_city]
    Asset_Avail=[Asset_Avail; HH_data(FFF,2), ageGroup, n_SA, n_city, tried_SA, tried_city, success_SA, success_city];

    if isempty(new_a)
        HH_ID=[HH_ID;FFF1(j)];
    end
    LU=[LU;lu];
    new_A=[new_A;new_a];
    new_B=[new_B;new_b];
    HH_change=[HH_change;hh_change];
end
