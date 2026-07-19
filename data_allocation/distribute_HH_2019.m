function distribute_HH_2019(HH_name,Build_name)
HH_name= 'HH_&_ind_data.mat';
Build_name = 'buildings&assets.mat';
load(HH_name)
load(Build_name)

u=unique(Build_Data(:,4));
u1=num2str(u);
for i=1:length(u)
    v=u1(i,1:end-4);
    locA=ismember(Build_Data(:,4),u(i));
    Build_Data(locA,12)=str2num(v);   
end
Build_Data_p=[Build_Data_p,'yeshuv'];

[Build_Data,Build_Data_p]=find_near_build_far(Build_Data,Build_Data_p,Assets);

[~,locB]=ismember(Assets(:,2),Build_Data(:,1));
Assets(:,6)=Build_Data(locB,12);
Assets(:,7)=Build_Data(locB,8);
Assets(:,8)=Build_Data(locB,9);
Assets(:,9)=Build_Data(locB,14);
Assets(:,10)=Build_Data(locB,16);

[~,locB]=ismember(HH_data(:,1),Build_Data(:,4));
HH_data(:,9)=Build_Data(locB,12);
HH_data_P=[HH_data_P,'yeshuv'];


Assets_P=[Assets_P,'yeshuv','travel time','travel dis','near TT','near P'];
u=unique(Build_Data(:,12));

%%
sum_data_P={'yeshuv','Coefficient1','Coefficient2','SE1','SE2','corr'};
for i=1:length(u)
    s_data=Assets(Assets(:,6)==u(i),:);
    s=size(s_data,1);
    x=s_data(:,7);
    x1=log(x);
    y=s_data(:,8);
    y1=log(y);
    mdl = fitlm(x1,y1);
    
    sum_data(i,1)=u(i);
    sum_data(i,2:3)=table2array(mdl.Coefficients(2,1));
    sum_data(i,4:5)=table2array(mdl.Coefficients(2,2));
    sum_data(i,6)=mdl.CoefficientCovariance(2,2);

    mu1=nanmean(s_data(:,7)./s_data(:,5));
    mu=sum_data(i,2)+sum_data(i,3)*mu1;
    sigma=sum_data(i,4)^2+sum_data(i,5)^2+2*sum_data(i,6)*sum_data(i,4)*sum_data(i,5);
    
    v=(HH_data(:,9)==(u(i)));
  
    HH_income_hour=nanmean(HH_data(v,6))/144;
    tq=s_data(:,7).*s_data(:,4);
    kt_ass=HH_income_hour.*s_data(:,7)*22;
    kt_near_ass=HH_income_hour.*s_data(:,9)*22;
    
    deltaT=s_data(:,9)-s_data(:,7);
    deltaK=(kt_near_ass-kt_ass);
    deltaP=s_data(:,10)-s_data(:,5);
    delta=deltaP./deltaT+deltaK./deltaT;
    
    r = normrnd(mu,sigma,[sum(v),1]);
    v=find(v==1);
    
    for j=1:length(r)
        lur=r(j);
        di=HH_data(v(j),6)/3;
        
        lur_A=lur-(tq./(di-kt_ass).*delta);
        [m,mm]=min(abs(lur_A));
        
        HH_data(v(j),10:11)=s_data(mm(1),2:3);
        s_data(mm(1),:)=[];
        tq(mm(1))=[];
        kt_ass(mm(1))=[];
        delta(mm(1))=[];       
    end  
end
    
HH_data_P=[HH_data_P,'building id','ass id'];
HH_data(HH_data(:,10) == 0,:) = [];
HH_data(HH_data(:,11) == 0,:) = [];
locA=ismember(Assets(:,3),HH_data(:,11));
Assets(locA,11)=1;

Assets_P=[Assets_P,'occupied'];

save('data_after_lur','Build_Data', 'Build_Data_p','Assets','Assets_P','HH_data','HH_data_P','sa_data','sa_data_P','Individuals_data', 'Individuals_data_P')

