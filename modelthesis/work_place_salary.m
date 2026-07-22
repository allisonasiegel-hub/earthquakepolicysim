function DATA=work_place_salary(Work_places)
DATA=[];
u=unique(Work_places(:,2));
for i=1:length(u)
    sdata=Work_places(Work_places(:,2)==u(i),:);
    a=sdata(:,8)==0;
    M=mean(sdata(a==0,8));
    SE=std(sdata(a==0,8))/4;
    if isnan(M)
        M = nanmean(Work_places(:,8));
        SE = nanstd(Work_places(:,8));
    end
    s=sum(a);
    N=abs(normrnd(M,SE,[s,1]));
    sdata(a,8)=N;
    DATA=[DATA;sdata];
end

