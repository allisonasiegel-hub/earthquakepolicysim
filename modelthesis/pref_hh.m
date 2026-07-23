function [pref,num_worker,maxD,D_work,HH_house_xy,build_id,HH_age,work_xy]=pref_hh(pd,wresd,wservice,wservice_old,service_mean,service_std,Build_Data,Build_Distance_matrix_400,Assets,Individuals_data,HH_data,FFF1, stat_data)

% data for relevant HH
[num_worker,maxD,D_work,HH_house_xy,build_id,HH_age,work_xy]=HH_living_data(HH_data,FFF1,Individuals_data,Build_Data);

% data for all HH and agents in 400m radius
[HH_in_R,~,individuals_in_R]=find_in_radius(Build_Distance_matrix_400,Assets,HH_data,Individuals_data,build_id);

age_M=mean(individuals_in_R(:,6)); % avarage agents age
age_std=std(individuals_in_R(:,6)); % standard deviation

income_M=mean(HH_in_R(:,6)); % avarage income for relevat HH
income_std=std(HH_in_R(:,6));

% z score

income=(HH_data(FFF1,6)-income_M)/income_std; % (HH_income-mean_income)/stdev
income=pdf(pd,income)/pdf(pd,0); % gaussian distribution for income normalized by normal distribtion
age=(HH_age-age_M)/age_std; % age normalization
age=pdf(pd,age)/pdf(pd,0); % age distribution

%% ---------------------------------------------------------
%% Service preference (elderly households only)
%% ---------------------------------------------------------

isElderly = HH_data(FFF1,5) >= 2;

if isElderly

    idx = stat_data(:,1)==HH_data(FFF1,1);

    if any(idx)

        current_service = stat_data(idx,5); % dynamic, periodically-updated service ratio

        service = (current_service-service_mean)/service_std;
        

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



A=num_worker>0; % boolean
D_work=nanmean(D_work); % average distance form work
D_work(isnan(D_work))=0; % 0 for null data
B=wresd*D_work/maxD; % wresd=0.5
C=1-(A*wresd); 

pref=A*B+C*Y; % worker*(0.5*dis/max_dis) + (1-0.5*worker)*(income+age)/2