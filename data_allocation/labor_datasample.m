function [Individuals_data_labor,Individuals_data_P]=labor_datasample(Individuals_data_P,sa_data_P,sa_data,Individuals_data,stat_Labor_Force,stat_Labor_work...
    ,income1,income2,income3,income4,income5,income6,income7,income8,income9,income10)

stat_Labor_Force=find(strcmp(sa_data_P(1,:),stat_Labor_Force)==1);
stat_Labor_work=find(strcmp(sa_data_P(1,:),stat_Labor_work)==1);
income1=find(strcmp(sa_data_P(1,:),income1)==1);
income2=find(strcmp(sa_data_P(1,:),income2)==1);
income3=find(strcmp(sa_data_P(1,:),income3)==1);
income4=find(strcmp(sa_data_P(1,:),income4)==1);
income5=find(strcmp(sa_data_P(1,:),income5)==1);
income6=find(strcmp(sa_data_P(1,:),income6)==1);
income7=find(strcmp(sa_data_P(1,:),income7)==1);
income8=find(strcmp(sa_data_P(1,:),income8)==1);
income9=find(strcmp(sa_data_P(1,:),income9)==1);
income10=find(strcmp(sa_data_P(1,:),income10)==1);
income=[income1,income2,income3,income4,income5...
    income6,income7,income8,income9,income10];

%% labor
stat_Labor_Force=sa_data(1:end,stat_Labor_Force); % want to work
stat_Labor_work=sa_data(1:end,stat_Labor_work); % work
income=sa_data(1:end,income)./100;
Mean_income=nanmean(income);

u=unique(Individuals_data(:,2));
u(isnan(u))=[];
Individuals_data_labor=[];

W=[8,2]; % working probability, W1=A, W2=eld

% W_I grops(age,work)[2,0],[2,1],[2,2],[3,0],[3,1],[3,2]
W_I=[4	3	8	5	2	6; % mu
    2	2	2	2	2	2; %sig
    5	5	5	5	5	5]; % scale

for i=1:length(u)
    s_data=Individuals_data(Individuals_data(:,2)==u(i),:);
    
    %% working
    labor_force=find(s_data(:,6)>=2);
    weights=s_data(labor_force,6);
    weights(weights==2)=W(1);
    weights(weights==3)=W(2);
    
    want_work=datasample(labor_force,round(length(labor_force).*stat_Labor_Force(i)/100),'replace',false,'Weights',weights);
    s_data(want_work,12)=1;
    work=datasample(want_work,round(length(want_work).*stat_Labor_work(i)/100),'replace',false);
    s_data(work,12)=2;
    
    %% income
    income(i,isnan(income(i,:)))=Mean_income(isnan(income(i,:)));
    income(i,:)=income(i,:)/sum(income(i,:));
    Ns=1;
    Ne=10;
    N=Ns:Ne;
    pop=size(labor_force,1);
    Weights=s_data(labor_force,[6,12]);
    XX=1;
    
    JJ=[2,3];
    KK=[0,1,2];
       
    for jj=1:2
        for kk=1:3
            WWW1=labor_force(Weights(:,1)==JJ(jj) & Weights(:,2)==KK(kk));
            weights=cal_weights(W_I(1,XX),W_I(2,XX),W_I(3,XX),N);
            IND_income=(income(i,:)+weights)/sum(income(i,:)+weights);
            IND_income=abs(IND_income)./sum(abs(IND_income));
            
            %    length(WWW1)
            %    N
            %    IND_income
            I=randsrc(length(WWW1),1,[N;IND_income]);
            s_data(WWW1,13)=I;
            
            XX=XX+1;
        end
    end   
    Individuals_data_labor=[Individuals_data_labor;s_data];   
end
Individuals_data_P=[Individuals_data_P,'working status','Asiron'];