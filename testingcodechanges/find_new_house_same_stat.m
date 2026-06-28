function [HH_ID,HH_data,Assets,HH_change,LU,new_A,new_B,Build_Data,Asset_Avail]...
    =find_new_house_same_stat(HH_ID,pd,wservice,service_mean,service_std,stat_data,HH_data,Individuals_data,Build_Data,...
    Build_Distance_matrix_400,Assets,wresd,FFF1,LU,new_A,new_B,HH_change,Asset_Avail)

for j=1:size(FFF1,1)
    lu=[];
    new_b=[];
    hh_change=[];
    new_a=[];
    FFF=find(HH_data(:,2)==FFF1(j)); % moving HH ID
    SA=HH_data(FFF,1); % stat
    income=HH_data(FFF,6); %income
    Yeshuv=HH_data(FFF,9);% yeshuv
    IX=1;
    possible_assets=Assets(Assets(:,1)==SA & Assets(:,11)==0 & Assets(:,13)<=0.33*income ,:); % same SA ; empty asset ; greater then income threshold
    possible_assets_Y=Assets(Assets(:,1)~=SA & Assets(:,6)==Yeshuv & Assets(:,11)==0 & Assets(:,13)<=IX*income,:); % other SA ; same yeshuv ; empty asset ; greater then income threshold
    possible_assets_O=Assets(Assets(:,1)~=SA & Assets(:,6)~=Yeshuv & Assets(:,11)==0 & Assets(:,13)<=IX*income,:); % other SA ; other yeshuv ; empty asset ; greater then income threshold

    % track number of possible assets available to this HH (elderly focus)
    isElderly=HH_data(FFF,5)>=2;
    n_avail=size(possible_assets,1)+size(possible_assets_Y,1)+size(possible_assets_O,1);
    Asset_Avail=[Asset_Avail;HH_data(FFF,2),isElderly,n_avail]; % [HH_ID, isElderly, num_possible_assets]

    if size(possible_assets,1)>0 % same SA
        [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change]=new_house(possible_assets,Assets,HH_data,Build_Data,FFF); % assign new house
    elseif size(possible_assets_Y,1)>0 % other SA same yeshuv
        [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change]=find_new_house_sa_score(pd,wservice,service_mean,service_std,stat_data,HH_data,Individuals_data,Build_Data,...
		Build_Distance_matrix_400,Assets,wresd,FFF,possible_assets_Y); % assign new house
    end
    
    if isempty(new_a)
        [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change]=find_new_house_sa_score(pd,wservice,service_mean,service_std,stat_data,HH_data,Individuals_data,Build_Data...
            ,Build_Distance_matrix_400,Assets,wresd,FFF,possible_assets_O);
        if length(new_a)==4
            new_a(:,2)=3;
        end
    end
    % if did not find house delete
    if isempty(new_a)
        HH_ID=[HH_ID;FFF1(j)];
    end
    LU=[LU;lu];
    new_A=[new_A;new_a];
    new_B=[new_B;new_b];
    HH_change=[HH_change;hh_change];
    
end