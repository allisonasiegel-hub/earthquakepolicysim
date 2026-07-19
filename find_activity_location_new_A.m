function [BU1]=find_activity_location_new_A(Individuals_data,Build_Data,Work_places,HH_data,Wact1,Wact2,wactsnum,SA_data,id,BU)

BU1=BU; % building usage - Building_routine_id
BU1(ismember(BU(:,1),id),:)=[]; % match agent ID
Individuals_data=Individuals_data(ismember(Individuals_data(:,1),id),:); % update agents list
%% same as find_activity_location

car=Individuals_data(:,19)>0; % have car
age_3=Individuals_data(:,6)==3; % old
disability=sum(Individuals_data(:,7:11),2)>0; % any disability
AA=car-age_3-disability;

WW=wactsnum.*AA; % wactsum=3 ; 3*A[i]
WW=repmat(WW,1,size(SA_data,1)); % repeat vector as size of statistic areas

% first location - home
[~,locB]=ismember(Individuals_data(:,3),HH_data(:,2));
Houses=HH_data(locB,10);
[~,locB]=ismember(Houses,Build_Data(:,1));
locB(locB==0)=[];
X=Build_Data(locB,5);
Y=Build_Data(locB,6);
BU=Build_Data(locB,1);

% second location - work
[locA,~] = ismember(Individuals_data(:,17),Work_places(:,6)); % index of wp for each individual

a = (locA == 0) & (Individuals_data(:,17)~=99); % not working and not working outside
Individuals_data(a,12)=1; % update 'working status' 
Individuals_data(a,14)=0; % update 'income'
Individuals_data(a,15)=0; % update 'building_work_place'
Individuals_data(a,17)=0; % update 'work_place_id'
W=Individuals_data(:,12)==2 & Individuals_data(:,15)~=99 & Individuals_data(:,17)~=99; % 'working status' 'building_work_place'
Work_place=Individuals_data(W,17); % 'work_place_id'

[~,locB]=ismember(Work_place,Work_places(:,6)); % match workplace ID

X(W,2)=Work_places(locB(locB>0),3); % matching workplace x
Y(W,2)=Work_places(locB(locB>0),4); % workplace workplace y
X(W==0,2)=X(W==0,1); % copy building x
Y(W==0,2)=Y(W==0,1); % copy building y
BU(W,2)=Work_places(locB(locB>0),1); % workplace building ID
BU(W==0,2)=BU(W==0,1); % copy building ID

Individuals_data(W,20)=Individuals_data(W,20)-1; % 'number_of_activities' -1
Individuals_data(Individuals_data(:,20)<0,20)=0; % 'number_of_activities'<0 ; 'number_of_activities'=0 

last_location=[X(:,2),Y(:,2)]; 

%% all activities locations ; same as find_activity_location
usage=unique(Build_Data(:,3)); % building usage list with no repetitons
usage(usage==0)=[]; % remove zero members
u=max(Individuals_data(:,20)); % max activities 
xx=3; % col num
for i=1:u
    ind_data_u=Individuals_data(:,20)>=i; % person activity
    FFF=find(ind_data_u==1); % indexes of all activities eq 1
    pref=rand(sum(ind_data_u),1); % Random preference for activity location
    Usage=randsrc(sum(ind_data_u),1,usage'); % Random preference for activity Landuse
    
    for sss=1:size(SA_data,1) % SA SCORE for each individual 
        dis=pdist2(SA_data(sss,2:3),last_location(ind_data_u,:)); % calculate distance form person location
        SA_dis(:,sss)=dis; % transpose dis vector   
    end
    max_dis=max(SA_dis,[],2); % farest SA form agent
    Dagent=SA_dis./repmat(max_dis,1,size(SA_dis,2)); % distance for all agents 

    %% rep mat ; same as find_activity_location
    SA_SCORE=0.5.*(1-Dagent.*(1+WW(ind_data_u,:)));
    SA_SCORE=SA_SCORE+repmat(SA_data(:,4)',size(SA_SCORE,1),1);  % add building score for all agents
    clearvars dis SA_dis max_dis Dagent    
    SA_SCORE=SA_SCORE>repmat(pref,1,size(SA_SCORE,2)); % Score=true if score>pref
    
    %% if empty rand ; same as find_activity_location
    e=sum(SA_SCORE,2)==0;
    if sum(e)>0
        r=randsrc(sum(e),1,[1:size(SA_SCORE,2)]);
        f=find(e==1);
        I=sub2ind(size(SA_SCORE),f,r);
        SA_SCORE=double(SA_SCORE);
        SA_SCORE(I)=SA_SCORE(I)+1;
    end
    %% select area ; same as find_activity_location
    Rand=rand(size(SA_SCORE));
    Rand(isnan(SA_SCORE))=0;
    Rand(SA_SCORE==0)=0;
    [~,SA]=max(Rand,[],2);
    clearvars Rand SA_SCORE
    
    %% building score ; same as find_activity_location
    S=Build_Data(:,21);
    lock=Build_Data(:,24);
    S_data=[Build_Data(:,[1,3:6]),S,lock];
    S_data=S_data(S_data(:,6)>0 | isnan(S_data(:,6)),:);
    Usage(Usage>6)=1;
    
    SA=SA_data(SA,1); % whole row for index with max score
    u_sa=unique(SA(:,1)); % remove duplicate SA 
    u_usage=unique(Usage); % remove duplicate usage
    for iii=1:length(u_sa)
        for iiii=1:length(u_usage)
            f_sa=find(SA==u_sa(iii) & Usage==u_usage(iiii));
            Bui=S_data(S_data(:,3)==u_sa(iii) & S_data(:,2)==u_usage(iiii),:);
            if isempty(Bui)
                Bui=S_data(S_data(:,3)==u_sa(iii),:);
            end
            B=1:size(Bui,1);
            
            if nansum(Bui(:,end))==0
                no=ones(1,length(B)).*1./length(B);
            else
                no=Bui(:,end)'./nansum(Bui(:,end));
            end
            R=randsrc(length(f_sa),1,[B;no]);
            xxyy=Bui(R,4:5);
            bbbb=Bui(R,1);
            
            X(FFF(f_sa),xx)=xxyy(:,1);
            Y(FFF(f_sa),xx)=xxyy(:,2);
            BU(FFF(f_sa),xx)=bbbb(:,1);
            last_location(FFF(f_sa),:)=xxyy;
        end
    end
    xx=xx+1;    
end

BU=[Individuals_data(:,1),BU];
s1=size(BU1,2);
s=size(BU,2);
BU(:,s+1:s1)=nan; % add empty cols
BU1=[BU1;BU]; % append rows