function Work_places=new_works_after_recovery(Work_places,Build_Data,BI,average_wage,std_wage)
    
% 17 - 'work place'
% workplace 
locA=ismember(Build_Data(:,1),BI); % all recovered ID
new_jobs=Build_Data(locA,17); % matching workplace for recovered building
new_jobs=ceil(new_jobs.*1.7); % roundup workplaces*2
B_data=Build_Data(locA,:); % all data for recovered building
B_data(:,17)=new_jobs; % replace with new workplace value
    u=unique(new_jobs); 
    wp1=[];
    for i=1:length(u)
        data=[];
        data=repmat(B_data(new_jobs==u(i),:),u(i),1); % FAIL? row dim is data
        wp1=[wp1;data]; % append row
    end
    if size(wp1,1)>0 
    % 1 - 'BLDG_ID_x' ; 4 - 'SAID' ; 5 - 'X' ; 6 - 'Y' ; 17 - 'work place'
    WP=wp1(:,[1,4:6,17]);
    new_id=[max(Work_places(:,6))+1:max(Work_places(:,6))+size(WP,1)]'; % row(id+1) to row(id+size)
    WP(:,6)=new_id; % replace id
    WP(:,7)=0; % occupied=0
    std_wage_1 = std_wage/3; % standard devition /3
    N=normrnd(average_wage,std_wage_1,[size(WP,1),1]); % random normal distribution
    WP(:,8)=N; % replace salary with random
    Work_places=[Work_places;WP]; % append rows
    end
% 
% %% new jobs - com only
%         new_jobs=building_average_salary(building_average_salary(:,5)>20,1);
%         new_jobs_sa=normrnd(average_wage,std_wage,length(new_jobs),1);
%         occ=zeros(length(new_jobs),1);
%         new_id=[max(Work_places(:,6))+1:max(Work_places(:,6))+size(new_jobs,1)]';
%         for jjjj=1:length(new_jobs)
%             a=find(Work_places(:,1)==new_jobs(jjjj));
%             B_D(jjjj,:)=Work_places(a(1),1:4);
%         end
%         % {'building id','stat','X','Y','number of work places','id','occupied','salary'}
%         new_jobs_work_places=[B_D,nan(size(B_D,1),1),new_id,occ,new_jobs_sa];
%         Work_places=[Work_places; new_jobs_work_places];
%         