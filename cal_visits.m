function visit_volume=cal_visits(B,Build_Distance_matrix_400)
%% number of wp - smart calculation
B(:,1)=[]; % delete 'ind_id'
a=B(:,3)==B(:,2); % 'work (if no work than home id)' == 'other locations (building id)'
B(a,3)=nan; % fill nan 'other locations (building id)' 
B(:,2)=[]; % delete 'work (if no work than home id)'
X=unique(B); % unique ID list vector
X(isnan(X))=[]; % empty all nan 
X(X==0)=[]; % empty all zeros
H=histc(B(:),(X)); % histogram building id by unique ID bins
[locA,locb]=ismember(Build_Distance_matrix_400,X); % building within a distance matching ID

BBB=nan(size(Build_Distance_matrix_400)); % nan matrix
BBB(locA)=H(locb(locb>0)); % fill histogram values by index
visits=nansum(BBB,2); % sum rows 
visit_volume=[Build_Distance_matrix_400(:,1),visits]; % Building ID ; Visits count