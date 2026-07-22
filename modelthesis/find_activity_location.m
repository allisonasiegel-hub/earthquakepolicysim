function [BU,BU_P]=find_activity_location(Individuals_data,Build_Data,Work_places,HH_data,Wact1,Wact2,wactsnum,SA_data)
% 1 - living ; 2 - combined ; 3 - commercial ; 4 - industrial ; 5 - public ; 6 - senior 

%% Preparing the parameters for the calculations
car=Individuals_data(:,19)>0; % have car
age_3=Individuals_data(:,6)==3; % age is col(6)
disability=sum(Individuals_data(:,7:11),2)>0; % disability is col(7) to col(11)
AA=car-age_3-disability;

% SA Score pre-calculations (parameters build)
WW=wactsnum.*AA; % wactsum(default) = 3 ; A[i]/3
WW=repmat(WW,1,size(SA_data,1)); % repeat vector as size of statistic areas
%% first location - home (parameters build)

% 3 - 'HH id' ; 2 - 'HH ID'
[~,locB]=ismember(Individuals_data(:,3),HH_data(:,2)); % return the first index of HH for each individual
% 10 - 'building id'
Houses=HH_data(locB,10); % map all building for each relevant HH
% 1 - 'BLDG_ID_x'
[~,locB]=ismember(Houses,Build_Data(:,1)); % return the first index of bld for each HH
locB(locB==0)=[]; % slice all zeros
% 5 - 'X'
X=Build_Data(locB,5); % lon value of bld by index
% 6 - 'Y'
Y=Build_Data(locB,6); % lat value of bld by index
% 1 - 'BLDG_ID_x'
BU=Build_Data(locB,1); % building index

%% second location - work (parameters build)
% 12 - 'working status' ; 15 - 'building_work_place'
W=Individuals_data(:,12)==2 & Individuals_data(:,15)~=99; % W[i]=true for working and not home
% 17 - 'work_place_id'
Work_place=Individuals_data(:,17); % workplace id list
% 6 - 'id'
[~,locB]=ismember(Work_place,Work_places(:,6)); % return the first index of wp for each individual
% 3 - 'X'
X(W,2)=Work_places(locB(locB>0),3); % lon value of wp by person that is not zero
% 4 - 'Y'
Y(W,2)=Work_places(locB(locB>0),4); % lat value of wp by person that is not zero
X(W==0,2)=X(W==0,1); % fill zeros
Y(W==0,2)=Y(W==0,1); % fill zeros
% 1 - 'building id'
BU(W,2)=Work_places(locB(locB>0),1); % bld index of wp by person that is not zero
BU(W==0,2)=BU(W==0,1); % fill zeros

% 20 - 'number_of_activities'
Individuals_data(W,20)=Individuals_data(W,20)-1; % update person activity count
Individuals_data(Individuals_data(:,20)<0,20)=0; % reset person activity count
last_location=[X(:,2),Y(:,2)]; % 2d coordinates

%% all activities locations (parameters build)
% 3 - 'Usage'
usage=unique(Build_Data(:,3)); % create bld usage list with no repetitons
usage(usage==0)=[]; % remove zero members
% 20 - 'number_of_activities'
u=max(Individuals_data(:,20)); % max activities
xx=3; % col num
%% insert paramter values to matrix
for i=1:u
    ind_data_u=Individuals_data(:,20)>=xx-1; % person activity
    FFF=find(ind_data_u==1); % indexes of all activities eq 1
    pref=rand(sum(ind_data_u),1); % Random preference for activity location 
    Usage = datasample(usage, sum(ind_data_u), 'Replace', true); % Random preference for activity Landuse
    for sss=1:size(SA_data,1)
        % 2-3 - mean X,Y
        dis=pdist2(SA_data(sss,2:3),last_location(ind_data_u,:)); % calculate distance from person location
        SA_dis(:,sss)=dis; % transpose dis vector
    end
    
    max_dis=max(SA_dis,[],2); % farest SA form agent 
    Dagent=SA_dis./repmat(max_dis,1,size(SA_dis,2)); % distance for all agents 

    %% CALCULATION OF SA SCORE for each individual
    SA_SCORE=0.5.*(1-Dagent.*(1+WW(ind_data_u,:)));
    SA_SCORE=SA_SCORE+repmat(SA_data(:,4)',size(SA_SCORE,1),1); % add building score for all agents    
    clearvars dis SA_dis max_dis Dagent % reset values    
    SA_SCORE=SA_SCORE>repmat(pref,1,size(SA_SCORE,2)); % Score[i]=true if score>pref
    
    %% if empty rand
    e=sum(SA_SCORE,2)==0; % zero score for SA
    if sum(e)>0 % any score are 0 
        r=randsrc(sum(e),1,(1:size(SA_SCORE,2))); % random values for the number of empty score
        f=find(e==1); % all empty score rows
        I=sub2ind(size(SA_SCORE),f,r); % return the index in matrix
        SA_SCORE=double(SA_SCORE); % convert to double
        SA_SCORE(I)=SA_SCORE(I)+1; % assing values to random score 
    end
    %% select area
    Rand=rand(size(SA_SCORE)); % matrix with random values 0 to 1
    Rand(isnan(SA_SCORE))=0; % reset all zero score
    Rand(SA_SCORE==0)=0; % reset all zero score
    [~,SA]=max(Rand,[],2); % indexes of all max rows
    clearvars Rand SA_SCORE % reset values
    %% building score
    
    % 21 - 'b_score'
    S=Build_Data(:,21);%./(Wact1+Wact2); % bld score / 0.5+0.5 ; ????????
    % 1 - 'BLDG_ID_x' ; 3-6 - 'Usage'	'SAID'	'X'	'Y'
    S_data=[Build_Data(:,[1,3:6]),S]; % new metrix with score, id and coords
    S_data=S_data(S_data(:,6)>0 | isnan(S_data(:,6)),:);
    Usage(Usage>6)=1; % landuse pref is 1
    
    SA=SA_data(SA,1); % whole row for index with max score
    u_sa=unique(SA(:,1)); % remove duplicate SA 
    u_usage=unique(Usage); % remove duplicate usage
    for iii=1:length(u_sa) % for each SA
        for iiii=1:length(u_usage) % for each usage
            f_sa=find(SA==u_sa(iii) & Usage==u_usage(iiii)); % match id for SA and Usage
            % 2 - 'Usage' ; 3 - 'SAID'
            Bui=S_data(S_data(:,3)==u_sa(iii) & S_data(:,2)==u_usage(iiii),:); % select all rows that match id
            if isempty(Bui) % no match
                Bui=S_data(S_data(:,3)==u_sa(iii),:); % create only with SA id match
            end
            B=1:size(Bui,1); % row vector
            
            if nansum(Bui(:,end))==0 % all scores are zeros
                no=ones(1,length(B)).*1./length(B); % same values - 1/len
            else
                no=Bui(:,end)'./nansum(Bui(:,end)); % same values - x/sum(col(6))
            end
            R=randsrc(length(f_sa),1,[B;no]); % col of random calculated values
            xxyy=Bui(R,4:5); % coords for all random buildings
            bbbb=Bui(R,1); % id for all random buildings
            
            X(FFF(f_sa),xx)=xxyy(:,1); % pair X coords with activity and building
            Y(FFF(f_sa),xx)=xxyy(:,2); % pair Y coords with activity and building
            BU(FFF(f_sa),xx)=bbbb(:,1); % pair bld ID with activity and building
            last_location(FFF(f_sa),:)=xxyy; % update last location matrix
        end
    end
    xx=xx+1; % update intration for new col as location memory    
end
% 1 - 'ind id'
BU=[Individuals_data(:,1),BU]; % add col(1) to bld usage
s=size(BU,2); % number of cols
BU(:,s+1:s+10)=nan; % add 10 empty cols 
BU_P={'ind_id','building id','work (if no work than home id)','other locations (building id)'}; % header row