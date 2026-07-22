function [Build_Data,Build_Data_p]=find_near_build_far(Build_Data,Build_Data_p,Assets)

for i=1:size(Build_Data,1)
    x=Build_Data(i,8);
    v=find(Build_Data(:,8)>x & Build_Data(:,3)==1);
    
    dis=pdist2(Build_Data(i,5:6),Build_Data(v,5:6));
    [~,hh]=min(dis);
    if isempty(v)==0
    
    F=nanmean(Assets(Assets(:,2)==Build_Data(v(hh(1)),1),5));
    Build_Data(i,13:16)=[Build_Data(v(hh(1)),[1,8,9]),F];
    else
        Build_Data(i,13:16)=nan;
    end
end
Build_Data_p=[Build_Data_p,'near_far_B','Travel time near B','Travel dis near B','price m'];

