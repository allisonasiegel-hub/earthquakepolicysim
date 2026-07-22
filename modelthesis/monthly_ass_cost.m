function [Assets,Assets_P]=monthly_ass_cost(HH_data,Assets,Assets_P,Pa)

% median income
M=nanmedian(HH_data(:,6));
M=M/3; 

% mean assets price
V=nanmean(Assets(:,12)); 
Vs=nanstd(Assets(:,12));
% prevent division by zero if all prices are identical
if Vs==0
    Vs = eps; % use minimal positive value
end

A1=Assets(:,12)-V; % price-(mean price)
B=Vs*Pa; % Pa=12 ; % (standard deviation)*(12)
AV=M.*(1+(A1./B)); % median/3*( 1+ (price-(mean price))/(standard deviation)*(12))
Assets(:,13)=AV; % new col(13)
Assets_P=[Assets_P,'cost of life']; % header for col(13)