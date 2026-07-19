function SA_data=SA_score(Build_Data)

SA=unique(Build_Data(:,4)); % sort and remove duplicate col(4) - 'SAID'
for i=1:length(SA)
    B=Build_Data(Build_Data(:,4)==SA(i),:); % temp sort entire matrix by SAID
    SA_data(i,1)=SA(i); % col(1) - 'SAID'
    SA_data(i,2:3)=nanmean(B(:,[5,6])); % col(2) - mean X ; col(3) - mean Y
    SA_data(i,4)=max(B(:,21)); % col(4) - max 'b_score'
end

