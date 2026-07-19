function Individuals_data=create_disa(sa_data_P,sa_data,Individuals_data,dis1,dis2,dis3,dis4,dis5,stat)
Individuals_data=[(1:size(Individuals_data,1))',Individuals_data];
dis1=find(strcmp(sa_data_P(1,:),dis1)==1);
dis2=find(strcmp(sa_data_P(1,:),dis2)==1);
dis3=find(strcmp(sa_data_P(1,:),dis3)==1);
dis4=find(strcmp(sa_data_P(1,:),dis4)==1);
dis5=find(strcmp(sa_data_P(1,:),dis5)==1);
stat=find(strcmp(sa_data_P(1,:),stat)==1);

disabiliti=sa_data(:,[stat,dis1,dis2,dis3,dis4,dis5]);
W=[1,1,1,1,1;
    2,2,2,2,2;
    4,4,4,4,4];
for i=1:size(sa_data,1)
    for j=2:size(disabiliti,2)
        pop=sum(Individuals_data(:,2)==sa_data(i,1));
        y=disabiliti(disabiliti(:,1)==sa_data(i,1),j)/100.*pop;
        ind=Individuals_data(:,2)==sa_data(i,1);
        weights=Individuals_data(ind,6);
        weights(weights==1)=W(1,j-1);
        weights(weights==2)=W(2,j-1);
        weights(weights==3)=W(3,j-1);
        weights=weights./sum(weights);
        HHH=datasample(Individuals_data(ind,1),round(y),'Weights',weights');
        locA=ismember(Individuals_data(:,1),HHH);
        Individuals_data(locA,6+j-1)=1;
    end
end
