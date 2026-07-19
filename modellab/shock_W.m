function [Work_places,lost_jobs]=shock_W(Work_places,destroyed_B)
loca=ismember(Work_places(:,1),destroyed_B(:,1));
lost_jobs=Work_places(loca,6);
Work_places(loca,:)=[];