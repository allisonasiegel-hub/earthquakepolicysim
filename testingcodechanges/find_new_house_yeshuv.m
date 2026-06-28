function [HH_ID,HH_data,Assets,HH_change,LU,new_A,new_B,Build_Data,Asset_Avail]...
    =find_new_house_yeshuv(HH_ID,pd,wservice,service_mean,service_std,stat_data,HH_data,Individuals_data,Build_Data...
    ,Build_Distance_matrix_400,Assets,wresd,FFF1,LU,new_A,new_B,HH_change,Asset_Avail)

% Similar to find_new_house_same_stat without same SA condition

for j=1:size(FFF1,1)
    lu=[];
    new_b=[];
    hh_change=[];
    new_a=[];
    FFF=find(HH_data(:,2)==FFF1(j));
    SA=HH_data(FFF,1); % stat
    income=HH_data(FFF,6); %income
    Yeshuv=HH_data(FFF,9);% yeshuv
    IX=1;
    possible_assets_Y=Assets(Assets(:,1)~=SA & Assets(:,6)==Yeshuv & Assets(:,11)==0 & Assets(:,13)<=IX*income,:);
    possible_assets_O=Assets(Assets(:,1)~=SA & Assets(:,6)~=Yeshuv & Assets(:,11)==0 & Assets(:,13)<=IX*income,:);

    % track number of possible assets available to this HH (elderly focus)
    isElderly=HH_data(FFF,5)>=2;
    n_avail=size(possible_assets_Y,1)+size(possible_assets_O,1);
    Asset_Avail=[Asset_Avail;HH_data(FFF,2),isElderly,n_avail]; % [HH_ID, isElderly, num_possible_assets]

    if size(possible_assets_Y,1)>0
        [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change]=find_new_house_sa_score(pd,wservice,service_mean,service_std,stat_data,HH_data,Individuals_data...
            ,Build_Data,Build_Distance_matrix_400,Assets,wresd,FFF,possible_assets_Y);
    end
    
    if isempty(new_a) && size(possible_assets_O,1)>0
        [Assets,HH_data,Build_Data,lu,new_a,new_b,hh_change]=find_new_house_sa_score(pd,wservice,service_mean,service_std,stat_data,HH_data,Individuals_data...
            ,Build_Data,Build_Distance_matrix_400,Assets,wresd,FFF,possible_assets_O);
        if length(new_a)==4
            new_a(:,2)=3;
        end
    end
    
    %% if did not find house delete - move out side
    if isempty(new_a)
       HH_ID=[HH_ID;FFF1(j)];
    end
    LU=[LU;lu];
    new_A=[new_A;new_a];
    new_B=[new_B;new_b];
    HH_change=[HH_change;hh_change];
    
end