function [Build_Data,Build_Data_p]=building_score(Build_Data,Build_Data_p,Assets,wact1,wact2,Build_Distance_matrix)
% calculate building size = floor area * number of floors
FS=Build_Data(:,7).*Build_Data(:,11);
% find all usages
usage=unique(Build_Data(:,3));

%% number of HH in building - smart calculation
X=unique(Assets(Assets(:,11)==1,2)); % unique building id for occupied assets 
Y=Assets(Assets(:,11)==1,2); % all accupied assets
H=histc(Y,(X)); % histogram for assets per building

[~,locb]=ismember(X,Build_Data(:,1));
Build_Data(locb,20)=H'; % number of HH in building
Build_Data_p=[Build_Data_p,'number of HH in building'];
max_HH=max(H);

%% sum number of buildings in 250m
B_in_250=[Build_Distance_matrix(:,1),nansum(Build_Distance_matrix(:,2:end)>0,2)];
B_in_250(B_in_250(:,2)<1,2)=0.5;

%% sum number of empty buildings in 250m
[locA,locB]=ismember(Build_Distance_matrix,Build_Data(:,1));
empty_buildings=zeros(size(locB));

empty_buildings(locA)=Build_Data(locB(locB>0),18);
empty_buildings(Build_Distance_matrix==0 | isnan(Build_Distance_matrix))=nan;
sum_empty_buildings=nansum(empty_buildings(:,2:end),2);
k=[];

A=wact1.*(FS./max(FS).*(Build_Data(:,3)>1)+Build_Data(:,20)./max_HH.*(Build_Data(:,3)==1));
non_empty=B_in_250(:,2)-sum_empty_buildings;
B=non_empty./B_in_250(:,2).*wact2;
B_score=A+B;
B_score(B_score<0)=0;
Build_Data(:,21)=B_score;
Build_Data(Build_Data(:,3)==0,21)=0;
Build_Data_p=[Build_Data_p,'b_score'];
