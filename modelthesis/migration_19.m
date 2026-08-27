%added HHtrack to this function, should remove it if you remove the tracker


function    [Assets,HH_data,Individuals_data,Work_places,routine,new_A, HH_MOVE_TRACK]=...
            migration_19(Assets,sas_data,HH_data,Individuals_data,Work_places,new_A, HH_MOVE_TRACK, Build_Data, real_growth_rate)
%% get data
routine=[];
total_families=0;
% BUG FIX: previously used sas_data(i,5) ('inOutRatio', a dimensionless
% in/out migration ratio) directly as if it were an annual fraction of
% vacant housing to fill (x=inOutRatio/365, multiplied by free_assets).
% That produced ~21x too much population growth versus real Tiberias
% census data (TVR/growthrates1.xlsx, "Percentage annual growth in the
% Israeli population" per SA -- real average +1.11%/year, model was
% producing ~+23%/year). real_growth_rate is now the actual per-SA annual
% growth rate from that census data, applied to the model's CURRENT
% household count in that SA (not free_assets, which is now only a cap on
% how many new households can actually find housing). Negative real rates
% are clipped to 0 here since this function only ever adds households --
% real population decline in those SAs is expected to come through the
% existing eviction/departure pathways elsewhere in the model, not by
% migration_19.m removing households itself.
for i=1:size(sas_data,1)
    free_assets=sum(Assets(Assets(:,1)==sas_data(i,1),11)==0); % unoccupied assets within SA count
    current_hh_count=sum(HH_data(:,1)==sas_data(i,1)); % current households in SA
    [~,locG]=ismember(sas_data(i,1),real_growth_rate(:,1));
    if locG>0
        annual_rate=real_growth_rate(locG,2);
    else
        annual_rate=mean(real_growth_rate(:,2)); % fallback: city-wide average
    end
    daily_rate=max(0,annual_rate)/365;
    expected_new=daily_rate*current_hh_count;
    % BUG FIX: round(normrnd(expected_new,expected_new/3)) essentially
    % never produces a nonzero count when expected_new is small (which is
    % most of the time here -- real per-SA rates give expected_new mostly
    % in the 0.01-0.25/day range). round() needs the draw to cross 0.5,
    % and a Normal(mean, mean/3) distribution puts that ~3 sigma away for
    % mean=0.25 and much further for smaller means -- confirmed by a
    % diagnostic trace showing families_precap==0 for every SA on every
    % day of a 760-day run, i.e. zero migration arrivals city-wide the
    % entire run despite real_growth_rate being correctly positive for
    % most SAs. A Poisson draw is the standard, correct way to convert a
    % small expected rate into a random discrete count -- e.g.
    % Poisson(0.1) is ~90% chance of 0, ~9% chance of 1, ~0.5% chance of
    % 2, instead of practically always 0.
    if expected_new>0
        families=poissrnd(expected_new);
    else
        families=0;
    end
    families=max(0,min(families,free_assets)); % can't exceed actual vacancy

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
            % Only assets in buildings still zoned residential can be
            % assigned to new arrivals (see filter_residential_assets.m).
            possible_assets=filter_residential_assets(possible_assets, Build_Data);
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
                HH_MOVE_TRACK = [HH_MOVE_TRACK;

                HH_id,...           % HH ID
                new_HH(1),...       % Original SA
                new_HH(5),...       % Elderly count
                NaN,...             % Final SA
                0,...               % Displaced
                0];                 % Left city
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
