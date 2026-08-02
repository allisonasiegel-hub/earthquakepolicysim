function    [Assets,HH_data,Individuals_data,Work_places,routine,new_A]=...
            migration_19(Assets,sas_data,HH_data,Individuals_data,Work_places,new_A)
%% get data
routine=[];
total_families=0;
for i=1:size(sas_data,1)
    free_assets=sum(Assets(Assets(:,1)==sas_data(i,1),11)==0); % unoccupied assets within SA count
    x=sas_data(i,5)/52; % 5 - 'inOutRatio' - annual rate over 52 weekly steps (was /365 for daily steps)
    families=round(normrnd(x,x/3)*free_assets); % random*assets

    if families>0 
        families=datasample(HH_data,families); % random HH
        individuals=ismember(Individuals_data(:,3),unique(families(:,2))); % matching HH ID 
        individuals=Individuals_data(individuals,:); % copy rows
        
        for j=1:size(families,1)
            new_HH=[]; 
            new_individuals=[];
            new_a=[];
            income=families(j,6); % 'HH_income'
            %% FIND HOUSE 
            % matchnig ID ; unoccupied ; 'cost of life' <= 0.33*income
            possible_assets=Assets(Assets(:,1)==sas_data(i,1) & Assets(:,11)==0 & Assets(:,13)<=0.33*income,:);
            if  size(possible_assets,1)>1
                selected_A=datasample( possible_assets,1); % random asset from list
            elseif size(possible_assets,1)==1 
                selected_A=possible_assets; % only one asset matching
            else
                selected_A=[]; % not matching assets
            end

            if ~isempty(selected_A)
                Assets(Assets(:,3)==selected_A(3),11)=1; % mark assets as occupied
                new_a(:,1)=selected_A(3);
                new_a(:,2)=4;
                new_a(:,3)=selected_A(1);
                new_a(:,4)=99;
                new_HH=families(j,:); % select HH
                HH_id=max(HH_data(:,2))+1; % ID+1
                old_id=new_HH(2);
                new_HH(2)=HH_id;
                new_HH([1,9:11])=Assets(Assets(:,3)==selected_A(3),[1,6,2:3]); % SA ; zone ; building ; asset
                HH_data=[HH_data;new_HH]; % apped row of new HH
                new_individuals=individuals(individuals(:,3)==old_id,:); % agents within HH
                new_individuals(:,15:17)=0; % 'building_work_place' ; 'stat_work_place' ; 'work_place_id'
                new_individuals(:,3)=HH_id; % update HH
                new_individuals(:,1)=(max(Individuals_data(:,1))+1: max(Individuals_data(:,1))+size(new_individuals,1))'; % new Agent ID
                %% working
                W=sum(new_individuals(:,12)==2); % 'working status'=2
                f=find(Work_places(:,7)==0); % open workplaces
                if W<=size(f,1) && W>0
                    f=find(Work_places(:,7)==0);
                    f=datasample(f,W,'replace',false);
                    Work_places(f,7)=1;
                    % 12 - 'working status' ; 15 - 'building_work_place' ; 16 -'stat_work_place' ; 17 - 'work_place_id'
                    new_individuals(new_individuals(:,12)==2,15:17)=Work_places(f,[1,2,6]);
                    salaries=Work_places(f,8);
                    new_individuals(new_individuals(:,12)==2,14)=salaries;
                elseif W>size(f,1) && W>0
                f=find(Work_places(:,7)==0);
                F=find(new_individuals(:,12)==2);
                new_individuals(F(1:length(f)),15:17)=Work_places(f,[1,2,6]);
                new_individuals(F(length(f)+1:end),12)=1;                   
                else
                    new_individuals(new_individuals(:,12)==2,12)=1;                    
                end
                routine=[routine;new_individuals(:,1)]; % add agents id 
                Individuals_data=[Individuals_data;new_individuals]; % update Agents list
            end
            new_A=[new_A;new_a];
        end
    end
end    
