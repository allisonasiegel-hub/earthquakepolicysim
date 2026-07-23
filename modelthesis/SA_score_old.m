function score=SA_score_old(pd,wresd,wservice,wservice_old,service_mean,service_std,Build_Data,Individuals_data,HH_data,FFF1,u,stat_data)
% same calculation as in HH_living_data
hh_id=HH_data(FFF1,2); % moving HH ID
ind=Individuals_data(Individuals_data(:,3)==hh_id,:); % agents in HH 
num_worker=sum(ind(:,12)==2); % 
HH_house_xy=Build_Data(Build_Data(:,1)==HH_data(FFF1,10),5:6);
build_id=HH_data(FFF1,10);
maxD=max(pdist2(HH_house_xy,Build_Data(Build_Data(:,4)==u,[5:6])));
if maxD==0
    maxD=eps;
end
a=find(ind(:,12)==2);
D_work=0;
for i=1:num_worker
    work_b=ind(a(i),15);
    dis=pdist2(Build_Data(Build_Data(:,1)==work_b,[5:6]),HH_house_xy);
    if size(dis,1)>0
    D_work(i)=max(dis);
    end
end

% same calculation as in pref_hh

age_M=mean(Individuals_data(Individuals_data(:,2)==u,6));
age_std=std(Individuals_data(Individuals_data(:,2)==u,6));

income_M=mean(HH_data(HH_data(:,1)==u,6));
income_std=std(HH_data(HH_data(:,1)==u,6));

% z score

income=(HH_data(FFF1,6)-income_M)/income_std;
income=pdf(pd,income)/pdf(pd,0);
age=(mean(ind(:,6))-age_M)/age_std;
age=pdf(pd,age)/pdf(pd,0);


%% ---------------------------------------------------------
%% Service preference (elderly households only)
%% ---------------------------------------------------------

isElderly = HH_data(FFF1,5) >= 2;

if isElderly

    idx = stat_data(:,1)==u;

    if any(idx)

        candidate_service = stat_data(idx,5); % dynamic, periodically-updated service ratio

        service = (candidate_service-service_mean)/service_std;

    else

        service = 0;

    end

    % Old-old (70+) vs young-old (65-69) differentiation. Old-old takes
    % priority: a household with >=1 old-old member counts as old-old; an
    % elderly household with 0 old-old members is young-old. Requires
    % HH_data col 12 (old_old_count), only present in .mat files built
    % after the age-split addition (e.g. data_for_model_tmine_agesplit70.mat).
    isOldOld = HH_data(FFF1,12) >= 1;
    wservice_hh = wservice;
    if isOldOld
        wservice_hh = wservice_old; % higher weight for old-old households
    end
    Y = (income + age + wservice_hh*service)/(2+wservice_hh);

else

    Y = (income + age)/2;

end


A=num_worker>0;
D_work=nanmean(D_work);
D_work(isnan(D_work))=0;
B=wresd*D_work/maxD;
C=1-(A*wresd);

score=A*B+C*Y;