function [HH_data,HH_data_P]=car_number(HH_data,HH_data_P,sa_data)

%% one car sa data=11
%% 2 cars sa data =12
cars=sa_data(1:end,11:12)./100;
Mean_cars=nanmean(cars);

HH_data_car=[];
%% weights - vowning more than 1 car
% income quantile	1	1	1	2	2	2	3	3	3	4	4	4
% household size	up to 2	3 or 4	5 and more	up to 2	3 or 4	5 and more	up to 2	3 or 4	5 and more	up to 2	3 or 4	5 and more
u1=[	1	2	4	1.5	3	6	5	6.5	8	7.5	9	10];
sigma1	=[3	3	3	3	3	3	3	3	3	3	3	3];
scale1	=[5	5	5	5	5	5	5	5	5	5	5	5];
yair_weights1=[	-0.013002619	-0.012538344	-0.009698678	-0.012817669	-0.01154995	-0.002364071	-0.006666267	0.000168503	0.007998458	0.005496049	0.011860806	0.013298076];
W1=[u1;sigma1;scale1];

%%vowning more than 1 car
%% income quantile	1	1	1	2	2	2	3	3	3	4	4	4
%%chousehold size	up to 2	3 or 4	5 and more	up to 2	3 or 4	5 and more	up to 2	3 or 4	5 and more	up to 2	3 or 4	5 and more
u2=[	0.5	1.5	3.5	1	2.5	5.5	4.5	6.5	8.5	8	9.5	10];
sigma2=[	3	3	3	3	3	3	3	3	3	3	3	3];
scale2=[	5	5	5	5	5	5	5	5	5	5	5	5];
yair2=[	-0.013121344	-0.012817669	-0.010754568	-0.013002619	-0.012129523...
    -0.00466357	-0.008343998	0.000168503	0.010172946	0.007998458	0.012931238	0.013298076];
W2=[u2;sigma2;scale2];

%% stat data
u=unique(HH_data(:,1));
u(isnan(u))=[];

for i=1:length(u)
    s_data=HH_data(HH_data(:,1)==u(i),:);
    
    %% cars
    cars(i,isnan(cars(i,:)))=Mean_cars(isnan(cars(i,:)));
    car1=[1-cars(i,1),cars(i,1)];
    car2=[1-cars(i,2),cars(i,2)];
    N=[0,1];
    
    pop=size(s_data,1);
    Weights=s_data(:,[3,6]);
    Weights(Weights(:,1)<3,1)=1;
    Weights(Weights(:,1)>2 & Weights(:,1)<5,1)=2;
    Weights(Weights(:,1)>4,1)=3;
    P=prctile(Weights(:,2),[25,50,75]);
    Weights(Weights(:,2)<P(1),2)=1;
    Weights(Weights(:,2)>=P(1) & Weights(:,2)<P(2),2)=2;
    Weights(Weights(:,2)>=P(2) & Weights(:,2)<P(3),2)=3;
    Weights(Weights(:,2)>=P(3),2)=4;
    
    XX=1;
    for jj=1:3
        for kk=1:4
            WWW1=Weights(:,1)==jj & Weights(:,2)==kk;
            weights=cal_weights(W1(1,XX),W1(2,XX),W1(3,XX),N);
            IND_cars=(car1+weights)/sum(car1+weights);

            if IND_cars(1) < 0
                IND_cars(1) = 0;
            end    
            if IND_cars(2) >1
                IND_cars(2) = 1;
            end
            if IND_cars(2) < 0
                IND_cars(2) = 0.0005;
                IND_cars(1) = 0.9995;
            end
            IND_cars
            N
            sum(WWW1)
            I=randsrc(sum(WWW1),1,[N;IND_cars]);
            s_data(WWW1,8)=I;
            
            %% second car
            WWW1=Weights(:,1)==jj & Weights(:,2)==kk & s_data(:,8)==1;
            weights=cal_weights(W2(1,XX),W2(2,XX),W2(3,XX),N);
            IND_cars=(car2+weights)/sum(car2+weights);
            IND_cars=abs(abs(IND_cars)./sum(abs(IND_cars)));
            
            I=randsrc(sum(WWW1),1,[N;IND_cars])
            s_data(WWW1,8)=s_data(WWW1,8)+I;
            XX=XX+1;
        end
    end
    HH_data_car=[HH_data_car;s_data];
    
end

HH_data_P=[HH_data_P,'number of cars'];
HH_data=HH_data_car;

