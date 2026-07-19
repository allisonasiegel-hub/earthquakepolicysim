function [BU,BU_P]=find_activity_location(Individuals_data,Build_Data,Work_places,HH_data,Wact1,Wact2,wactsnum,SA_data)
% 1 - living ; 2 - combined ; 3 - commercial ; 4 - industrial ; 5 - public ; 6 - senior 

%% Preparing the parameters for the calculations
car          = Individuals_data(:,19) > 0;     % have car
age_3        = Individuals_data(:,6)  == 3;    % age is col(6)
disability   = sum(Individuals_data(:,7:11),2) > 0; % disability is col(7) to col(11)
AA           = car - age_3 - disability;

% SA Score pre-calculations (parameters build)
WW = wactsnum .* AA;                            % wactsum(default) = 3 ; A[i]/3
WW = repmat(WW,1,size(SA_data,1));              % repeat vector as size of statistic areas

%% first location - home (parameters build)

% 3 - 'HH id' ; 2 - 'HH ID'
[~,locB] = ismember(Individuals_data(:,3),HH_data(:,2));       % index of HH for each individual
% 10 - 'building id'
Houses   = HH_data(locB,10);                                   % map building for each HH
% 1 - 'BLDG_ID_x'
[~,locB] = ismember(Houses,Build_Data(:,1));                   % index of bld for each HH
locB(locB==0) = [];                                            % NOTE: original behavior kept
% 5 - 'X'
X = Build_Data(locB,5);                                        % lon value of bld by index
% 6 - 'Y'
Y = Build_Data(locB,6);                                        % lat value of bld by index
% 1 - 'BLDG_ID_x'
BU = Build_Data(locB,1);                                       % building index

%% second location - work (parameters build)
% 12 - 'working status' ; 15 - 'building_work_place'
W          = Individuals_data(:,12)==2 & Individuals_data(:,15)~=99; % working and not home
% 17 - 'work_place_id'
Work_place = Individuals_data(:,17);                            % workplace id list
% 6 - 'id'
[~,locB]   = ismember(Work_place,Work_places(:,6));            % index of wp for each individual

% 3 - 'X'
X(W,2)     = Work_places(locB(locB>0),3);                      % lon for workers with valid wp
% 4 - 'Y'
Y(W,2)     = Work_places(locB(locB>0),4);                      % lat for workers with valid wp
X(W==0,2)  = X(W==0,1);                                        % fill zeros
Y(W==0,2)  = Y(W==0,1);                                        % fill zeros
% 1 - 'building id'
BU(W,2)    = Work_places(locB(locB>0),1);                      % bld id for workers with valid wp
BU(W==0,2) = BU(W==0,1);                                       % fill zeros

% 20 - 'number_of_activities'
Individuals_data(W,20) = Individuals_data(W,20) - 1;           % update person activity count
Individuals_data(Individuals_data(:,20)<0,20) = 0;             % reset person activity count
last_location = [X(:,2),Y(:,2)];                                % 2d coordinates

%% all activities locations (parameters build)
% 3 - 'Usage'
usage = unique(Build_Data(:,3));                                % bld usage list without repetitions
usage(usage==0) = [];                                           % remove zero members
% 20 - 'number_of_activities'
u  = max(Individuals_data(:,20));                               % max activities
xx = 3;                                                         % starting column index for extra activities

%% Precompute S_data (building candidates) and sanitize scores
% 21 - 'b_score'
S      = Build_Data(:,21);
% 1 - 'BLDG_ID_x' ; 3-6 - 'Usage' 'SAID' 'X' 'Y'
S_data = [Build_Data(:,[1,3:6]), S];                            % [bld_id, usage, SAID, X, Y, score]
% Keep only positive, finite scores (drop NaN / Inf and <=0)
S_data = S_data(isfinite(S_data(:,6)) & S_data(:,6) > 0, :);

%% insert parameter values to matrix
for i = 1:u
    ind_data_u = Individuals_data(:,20) >= (xx - 1);            % person activity
    FFF        = find(ind_data_u==1);                           % indexes of all activities eq 1
    if isempty(FFF)
        xx = xx + 1;
        continue
    end

    pref  = rand(sum(ind_data_u),1);                            % Random preference for activity location 
    Usage = datasample(usage, sum(ind_data_u), 'Replace', true);% Random preference for activity Landuse

    % Build SA distance matrix
    SA_dis = zeros(sum(ind_data_u), size(SA_data,1));
    for sss = 1:size(SA_data,1)
        % 2-3 - mean X,Y
        dis = pdist2(SA_data(sss,2:3), last_location(ind_data_u,:)); % distance from person location
        SA_dis(:,sss) = dis; 
    end
    
    max_dis = max(SA_dis,[],2);                                 % farthest SA from agent 
    Dagent  = SA_dis ./ repmat(max_dis,1,size(SA_dis,2));       % normalized distance for all agents 

    %% CALCULATION OF SA SCORE for each individual
    SA_SCORE = 0.5.*(1 - Dagent .* (1 + WW(ind_data_u,:)));
    SA_SCORE = SA_SCORE + repmat(SA_data(:,4)', size(SA_SCORE,1), 1); % add SA score for all agents    
    clear dis SA_dis max_dis Dagent                              % reset values    
    SA_SCORE = SA_SCORE > repmat(pref,1,size(SA_SCORE,2));       % Score[i]=true if score>pref
    
    %% if empty rand
    e = sum(SA_SCORE,2) == 0;                                    % zero score for SA
    if any(e)                                                    % any score are 0 
        r = randsrc(sum(e), 1, (1:size(SA_SCORE,2)));            % random SA choices for empty rows
        f = find(e==1);                                          % all empty score rows
        I = sub2ind(size(SA_SCORE), f, r);                       % indices in matrix
        SA_SCORE = double(SA_SCORE);                             % convert to double
        SA_SCORE(I) = SA_SCORE(I) + 1;                           % assign a random valid SA
    end

    %% select area
    Rand               = rand(size(SA_SCORE));                   % random matrix in [0,1]
    Rand(isnan(SA_SCORE)) = 0;                                   % reset invalid
    Rand(SA_SCORE==0)  = 0;                                      % reset all zero score
    [~,SA_idx]         = max(Rand,[],2);                         % index of chosen SA per agent
    clear Rand SA_SCORE

    %% building choice inside chosen SAs
    % SA_idx are indices into SA_data rows; convert to SA IDs (col 1)
    SA_ids     = SA_data(SA_idx,1);                              % chosen SA IDs per agent
    u_sa       = unique(SA_ids(:));                              
    u_usage    = unique(Usage);

    for iii = 1:length(u_sa)          % for each SA
        for iiii = 1:length(u_usage)  % for each usage
            f_sa = find(SA_ids==u_sa(iii) & Usage==u_usage(iiii)); % people in this SA+usage bucket
            if isempty(f_sa)
                continue
            end

            % Candidate buildings for this SA/usage pair with robust fallbacks
            Bui = S_data(S_data(:,3)==u_sa(iii) & S_data(:,2)==u_usage(iiii), :); % exact SA+usage
            if isempty(Bui)
                Bui = S_data(S_data(:,3)==u_sa(iii), :);                           % fallback 1: any in SA
            end
            if isempty(Bui)
                Bui = S_data(S_data(:,2)==u_usage(iiii), :);                       % fallback 2: any with usage
            end
            if isempty(Bui)
                Bui = S_data;                                                      % fallback 3: any building
            end

            B = 1:size(Bui,1);                              % alphabet (row indices)
            if isempty(B)
                % No candidates at all: replicate last location and building as fallback
                X(FFF(f_sa),xx)  = last_location(FFF(f_sa),1);
                Y(FFF(f_sa),xx)  = last_location(FFF(f_sa),2);
                BU(FFF(f_sa),xx) = BU(FFF(f_sa),max(1,xx-1));
                continue
            end

            % Build a safe probability vector
            scores = Bui(:,end);                             % last col = score
            scores(~isfinite(scores)) = 0;                   % sanitize
            scores(scores < 0)       = 0;

            tot = sum(scores);
            if tot <= 0
                no = ones(1, numel(B)) / numel(B);           % uniform if all zero/invalid
            else
                no = (scores / tot).';                       % row vector
                no(~isfinite(no)) = 0;
                ssum = sum(no);
                if ssum <= 0
                    no = ones(1, numel(B)) / numel(B);
                else
                    no = max(0, min(1, no));
                    no = no / sum(no);
                end
            end

            % Draw building indices for all agents in this SA/usage bucket
            R = randsrc(length(f_sa), 1, [B; no]);           % (symbols; probs) rows

            xxyy = Bui(R,4:5);                               % [X,Y]
            bbbb = Bui(R,1);                                 % building id

            X(FFF(f_sa),xx)  = xxyy(:,1);                    % assign X
            Y(FFF(f_sa),xx)  = xxyy(:,2);                    % assign Y
            BU(FFF(f_sa),xx) = bbbb(:,1);                    % assign building id
            last_location(FFF(f_sa),:) = xxyy;               % update last location
        end
    end

    xx = xx + 1;                                             % next activity column
end

% 1 - 'ind id'
BU = [Individuals_data(:,1), BU];                           % add col(1) to bld usage
s  = size(BU,2);                                            % number of cols
BU(:,s+1:s+10) = nan;                                       % add 10 empty cols 
BU_P = {'ind_id','building id','work (if no work than home id)','other locations (building id)'}; % header row
end
