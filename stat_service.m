function [stat_service_ratio,stat_data]=stat_service(Build_Data,Individuals_data,HH_data)
u=unique(Build_Data(:,4));
for i=1:length(u)
    s_data=Build_Data(Build_Data(:,4)==u(i),3);
    com=sum(s_data>1 & s_data<4);
    pub=sum(s_data==5);
    res_count=sum(s_data==1);
    stat_service_ratio(i,1)=u(i);
    if res_count==0
        stat_service_ratio(i,2)=0; % avoid division by zero
    else
        stat_service_ratio(i,2)=(com+pub)/res_count;
    end
    
    s_data=HH_data(HH_data(:,1)==u(i),6);
    stat_service_ratio(i,3)=mean(s_data);
    
    s_data=Individuals_data(Individuals_data(:,2)==u(i),6);
    stat_service_ratio(i,4)=mean(s_data);
    
end

stat_data={'stat','service ratio','HH income', 'average age'};