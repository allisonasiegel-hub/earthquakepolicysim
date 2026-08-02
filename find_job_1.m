function  [agent_rot,Individuals_data,HH_data,Work_places]=find_job_1(HH_ID_left,Individuals_data,HH_data,Work_places,Build_Data,income99)
agent_rot=[];
ind=Individuals_data;
ind(:,21)=1:size(ind,1); % 21 - 'ind_id_empty' ; fill with integer 1 to size
% find the looking individuals use only them
ind=ind(ind(:,12)==1,:); % working status = 1
% delete individuals that left the world
loca=ismember(ind(:,3),HH_ID_left);
ind(loca,:)=[];

% delete working individuals that working outside
% find HH ID - house locations and work locations
% find working individuals houses - buildings- locations
[locA,locB]=ismember(ind(:,3),HH_data(:,2));
ind_houses=HH_data(locB(locB>0),10); % find HH(individual) house id
[locA,locB]=ismember(ind_houses,Build_Data(:,1));
ind_house_xy=Build_Data(locB(locB>0),5:6);

F_wp=find(Work_places(:,7)==0); % not occupied workplaces
for i=1:size(ind,1)
    pref = rand(length(F_wp),1);
    if size(pref,1)>0
        F=F_wp(ind(i,18)<=pref); % agent pref lower then rand pref
    else
        F=[];
    end
    if size(F,1)>0
        
        % 12 - 'working status';
        % 14 - 'income' = 8 - 'salary';
        % 15 - 'building_work_place' = 1 - 'building id';
        % 16 - 'stat_work_place' = 2 - 'stat'
    	% 17 - 'work_place_id' = 6 -'id';
        % 22 - 'time looking for job';
        Individuals_data(ind(i,21),[12,14,15,16,17,22])=[2,Work_places(F(1),[8,1:2,6]),0];
        % 7 - 'occupied' = (1); 
        Work_places(F(1),7)=1;
        % new income = old - agent income + salary
        HH_data(HH_data(:,2)==ind(i,3),6)=HH_data(HH_data(:,2)==ind(i,3),6)-ind(i,14)+Work_places(F(1),8);
        agent_rot=[agent_rot;ind(i,1)]; % agent ID list
        F_wp=find(Work_places(:,7)==0); 

    else
        T=1-exp((-1*ind(i,22))/(30/7)); % T = 1-e^(-('time looking for job')/(30/7)) - was /30 for daily steps, now ~4.29 weeks
        RRR=rand(1);
        RRR1=rand(1);
        if T>RRR
            IN=normrnd(income99(1),income99(2)); % normal rand num for out of world average and stdev
            IN(IN<1000)=1000; % lowest income is 1000           
            Individuals_data(ind(i,21),[12,14,15,16,17,22])=[2,IN,99,99,99,0]; % update fields 
            % new income = old - agent income + rand income99
            HH_data(HH_data(:,2)==ind(i,3),6)=HH_data(HH_data(:,2)==ind(i,3),6)-ind(i,14)+IN; 
            agent_rot=[agent_rot;ind(i,1)];
            
        elseif RRR1<T
            % agent left work or did not assigned
            Individuals_data(ind(i,21),[12,14,15,16,17,22])=[0,ind(i,14),0,0,0,0]; 
        else
            % agent keep looking time +1
            Individuals_data(ind(i,21),22)= Individuals_data(ind(i,21),22)+1;
        end
    end
end

