function distribute_workers(spatial_data,RZ,NAME)
load(spatial_data)
%% factor to creates more working places
Build_Data(:,17)=Build_Data(:,17).*RZ; % factor
a=round(Build_Data(:,17))>0;
working_places=Build_Data(a,:);
working_places(:,17)=round(working_places(:,17));
u=unique(working_places(:,17));
work_place=[];
for i=1:length(u)
    data=[];
    data=repmat(working_places(working_places(:,17)==u(i),:),u(i),1);
    work_place=[work_place;data];
end
%% read individual data
work_place(:,18)=1:size(work_place,1);
Work_places=work_place(:,[1,4:6,17,18]);
Work_places_P={'building id','stat','X','Y','number of work places','id','occupied','salary'};
Work_places(:,7)=0;
Work_places = Work_places(randperm(size(Work_places, 1)), :);
% divide individuals into work place
u=unique(Individuals_data(:,2));
metro_zone=[31,34];
WORKER=0;

for i=1:length(u)
    ind_sa=sa_data(sa_data(:,1)==u(i),48:50); % {'comm31','comm34','comm99'}
    F=find(Individuals_data(:,2)==u(i) & Individuals_data(:,12)==2); % ind that are working
    worker_Metro_zone=round(length(F)*ind_sa);
    WORKER=WORKER+sum(worker_Metro_zone(1:3));
    for j=1:2
        S=sa_data(sa_data(:,47)==metro_zone(j),1);
        [locA,locB]=ismember(work_place(:,4),S);
        B=find(locA==1);
        if length(B)>=worker_Metro_zone(j) && worker_Metro_zone(j)>0
            B=datasample(B,worker_Metro_zone(j),'replace',false);
            Individuals_data(F(1:worker_Metro_zone(j)),15:17)=work_place(B,[1,4,18]);
            
            ID=work_place(B,18);
            work_place(B,:)=[];
            
            locA=ismember(Work_places(:,6),ID);
            Work_places(locA,7)= Work_places(locA,7)+1;
            Work_places(locA,8)=Individuals_data(F(1:worker_Metro_zone(j)),14);
            F(1:worker_Metro_zone(j))=[];
        elseif ~isempty(B)
            % assign available workplaces even if fewer than requested
            B=datasample(B,length(B),'replace',false);
            num_assign=length(B);
            Individuals_data(F(1:num_assign),15:17)=work_place(B,[1,4,18]);
            ID=work_place(B,18);
            work_place(B,:)=[];

            locA=ismember(Work_places(:,6),ID);
            Work_places(locA,7)= Work_places(locA,7)+1;
            Work_places(locA,8)=Individuals_data(F(1:num_assign),14);

            F(1:num_assign)=[];
        end
    end
    f=length(F);
    if f>worker_Metro_zone(3)
        Individuals_data(F(1:worker_Metro_zone(3)),15:16)=99;
        F(1:worker_Metro_zone(3))=[];
        Individuals_data(F,12)=1;
    else
        Individuals_data(F,15:16)=99;
    end
end
 Individuals_data_P=[Individuals_data_P,'building_work_place','stat_work_place','work_place_id'];
 save(NAME,'HH_data','HH_data_P','Individuals_data','Individuals_data_P','Work_places_P','Work_places','Assets', 'Assets_P', 'Build_Data', 'Build_Data_p')