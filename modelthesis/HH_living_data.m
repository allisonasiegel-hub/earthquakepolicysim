function [num_worker,maxD,D_work,HH_house_xy,build_id,HH_age,work_xy]=HH_living_data(HH_data,FFF1,Individuals_data,Build_Data)

hh_id=HH_data(FFF1,2); % HH id
u=unique(HH_data(FFF1,1)); % unique SA for assets
ind=Individuals_data(Individuals_data(:,3)==hh_id,:); % all agents within HH
num_worker=sum(ind(:,12)==2); % 12 - 'working status' ; sum all avalible workers value 2
HH_house_xy=Build_Data(Build_Data(:,1)==HH_data(FFF1,10),5:6); % HH original coordinates
build_id=HH_data(FFF1,10); % building ID for relevant HH
maxD=max(pdist2(HH_house_xy,Build_Data(Build_Data(:,4)==u,5:6))); % FAIL?! only first SA ; max dist from first SA
if maxD==0
    maxD=eps;
end
a=find(ind(:,12)==2); % all working agents
D_work=0;
work_xy=[];
for i=1:num_worker
    work_b=ind(a(i),15); % 15 - 'building_work_place' ; workplace of each worker
    work_xy=[work_xy;Build_Data(Build_Data(:,1)==work_b,[5:6])]; % ccordinates for all workplaces in list
    dis=pdist2(Build_Data(Build_Data(:,1)==work_b,5:6),HH_house_xy); % distance from workplace to HH
    if size(dis,1)>0
        D_work(i)=max(dis); % save max distance
    end
end
HH_age=mean(ind(:,6)); % avarage agent age