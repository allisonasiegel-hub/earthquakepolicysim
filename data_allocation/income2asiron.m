function [HH_data,HH_data_P]=income2asiron(HH_data,HH_data_P,name)
data=xlsread(name);
for i=1:size(data,1)
    a=HH_data(:,6)>=data(i,2) & HH_data(:,6)<data(i,3);
    HH_data(a,7)=data(i,1)-1;
end
HH_data_P =[HH_data_P,'HH_asiron'];
