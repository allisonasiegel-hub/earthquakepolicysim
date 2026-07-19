function data=find_usage(data,file)

usage=xlsread([file,'USG_CODE_keys.csv']);
for i=1:size(usage,1)
   a=data(:,3)>=usage(i,1) & data(:,3)<=usage(i,2);
   data(a,3)=usage(i,3);
end
data(isnan(data(:,3)),3)=1;
data(data(:,3)==99,:)=[];


