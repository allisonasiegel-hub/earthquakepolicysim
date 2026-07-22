function [HH_data,old_old_count]=create_HH_12_2018(institute_65,sa_data,sa_data_P,data,total_65,HH_65_pcnt,HH_65_alone,HH_70_79_pcnt,HH_80_pcnt,HH1,HH2,...
    HH3,HH4,HH5,HH6,HH7,HH_child_total,...
    chil1,chil2,chil3,chil4,chil5)
HH_data=[];

%% old people
total_65=strcmp(sa_data_P(1,:),total_65)==1;
institute_65=strcmp(sa_data_P(1,:),institute_65)==1;
HH_65_pcnt=strcmp(sa_data_P(1,:),HH_65_pcnt)==1;
HH_65_alone=strcmp(sa_data_P(1,:),HH_65_alone)==1;
HH_70_79_pcnt=strcmp(sa_data_P(1,:),HH_70_79_pcnt)==1;
HH_80_pcnt=strcmp(sa_data_P(1,:),HH_80_pcnt)==1;

%% HH size
HH1=find(strcmp(sa_data_P(1,:),HH1)==1);
HH2=find(strcmp(sa_data_P(1,:),HH2)==1);
HH3=find(strcmp(sa_data_P(1,:),HH3)==1);
HH4=find(strcmp(sa_data_P(1,:),HH4)==1);
HH5=find(strcmp(sa_data_P(1,:),HH5)==1);
HH6=find(strcmp(sa_data_P(1,:),HH6)==1);
HH7=find(strcmp(sa_data_P(1,:),HH7)==1);

HH_size=[HH1,HH2,HH3,HH4,HH5,HH6,HH7];

%% number of children
HH_child_total=strcmp(sa_data_P(1,:),HH_child_total)==1;
chil1=find(strcmp(sa_data_P(1,:),chil1)==1);
chil2=find(strcmp(sa_data_P(1,:),chil2)==1);
chil3=find(strcmp(sa_data_P(1,:),chil3)==1);
chil4=find(strcmp(sa_data_P(1,:),chil4)==1);
chil5=find(strcmp(sa_data_P(1,:),chil5)==1);
HH_chil=[chil1,chil2,chil3,chil4,chil5];

ind=1;
for i=1:size(data,1)
    %% calculate number of HH
    stat_HH=[];
    stat=find(sa_data(:,1)==data(i,1));
    stat_HH=(ind:ind+data(i,2)-1)'; % stat HH
    stat_HH=[ones(size(stat_HH,1),1).*data(i,1),stat_HH];
    
    %% calculate numbet of eldery people
    num_65_target=round(sa_data(stat,HH_65_pcnt)*data(i,2)/100);
    num_65_alone=round(sa_data(stat,HH_65_alone)/100*num_65_target);
    stat_HH(1:num_65_alone,3)=1;
    stat_HH(1:num_65_alone,4)=3;
    HH_with_atleast_1_65=num_65_target-num_65_alone;

    % HH size
    stat_HH_size=floor(sa_data(stat,HH_size))/100;
    stat_HH_size=round(stat_HH_size.*data(i,2));
    H=sum(stat_HH_size);
    if size(stat_HH,1)>H
        stat_HH(H+1:end,:)=[];
    end
    
    % substract the number of hh size 1 by eldery people living alone
    stat_HH_size(1)=stat_HH_size(1)-sum(stat_HH(:,3)==1);
        
    k=find(stat_HH(:,3)==0,1,'first');
    for s=1:length(stat_HH_size)
        stat_HH(k:k+stat_HH_size(s)-1,3)=s;
        k=k+stat_HH_size(s);
    end
       
    %% children
    stat_HH_child = sa_data(stat,HH_chil) / 100;
    stat_HH_child(isnan(stat_HH_child)) = 0;
    stat_HH_child = stat_HH_child ./ sum(stat_HH_child);
    
    stat_HH_child_total = sa_data(stat,HH_child_total) / 100;
    family_with_children = round(stat_HH_child_total .* size(stat_HH,1));
    
    stat_HH_child = round(stat_HH_child .* family_with_children);
 
	child=length(stat_HH_child):-1:1;
    stat_HH(:,5)=zeros(size(stat_HH,1),1);
    for s=1:length(stat_HH_child)
        f=find(stat_HH(:,3)>child(s) & stat_HH(:,5)==0 & stat_HH(:,4)<3);
        if length(f)<stat_HH_child(child(s))
            stat_HH_child(child(s))=length(f);
        end
        f=datasample(f,stat_HH_child(child(s)),'replace',false);
        stat_HH(f,5)=child(s);         
    end
    %% delete extras HH
    stat_HH(stat_HH(:,1)==0,:)=[];
    %% find number of old in institutes
    % BUG FIX: this used to recompute num_65 here from total_65
    % (demog_yishuv.age_65_up, a population HEADCOUNT) via
    % round(sa_data(i,total_65)/100*sum(stat_HH(:,3))) -- dividing a raw
    % count by 100 and multiplying by SA population inflated it ~10x (e.g.
    % 79,615 "elderly" in a 2,681-household SA), which then got clamped by
    % the length(f) cap below to essentially "every eligible household",
    % badly over-assigning elderly households (38% vs census 27%). That
    % population-based estimate was also a different, incompatible basis
    % from num_65_target above (household-based, from HH_65_pcnt) -- the
    % two were being added together instead of reconciled. Fix: reuse
    % num_65_target consistently instead of recomputing from total_65.
    ins_65=round(sa_data(i,institute_65)/100*num_65_target);
    %% delete old in institutes and living alone
    extra_65=num_65_target-ins_65-sum(stat_HH(:,4)==3);
    %% find suitable HH (size of HH - number of kids) 
    f=(stat_HH(:,3)-stat_HH(:,5))>1;
    f=stat_HH(f,2);
    if length(f)<extra_65
        extra_65=length(f);
    end
    extra_65(isnan(extra_65))=0;
    extra_65(extra_65<0)=0;
    %% extra of old people = extras 65
    %% randomly choose hh - can be more than one eldery
    F=datasample(f,extra_65,'replace',true);
    a = unique(F);
    out = [a,histc(F(:),a)];
    
    %% delete 3 and choose new HH
    P1=out(:,2)>2;
    P=sum(out(P1,2))-sum(P1)*2;
       
    out(out(:,2)>2,2)=2;
    locA=ismember(stat_HH(:,2),out(:,1));
    stat_HH(locA,4)=out(:,2).*3;
        
    locA=ismember(f,F);
    f(locA)=[];
      
    F1=datasample(f,P,'replace',false);
    locA=ismember(stat_HH(:,2),F1);
    stat_HH(locA,4)=3;

    % ------------------------------------------------------------
    % split this SA's elderly (col4: 0/3/6) into young-old (65-69) vs
    % old-old (70+). col6 is scratch space, unused elsewhere in this
    % local array -- holds the old-old count per HH for this SA.
    % Additive only: col4's encoding (elderly household, >=2 check used
    % throughout the rest of the codebase) is untouched.
    %
    % pcnt_65 and pcnt_70 are both population-level percentages (not
    % HH_65_pcnt, which is a HOUSEHOLD share and runs systematically
    % higher than the population share for the same age group, since one
    % elderly member makes the whole household count -- mixing the two
    % would bias frac_70_among_old downward).
    % ------------------------------------------------------------
    stat_HH(:,6)=0;
    total_old_in_SA=sum(stat_HH(:,4))/3; % 3->1 elderly, 6->2 elderly
    total_pop=data(i,3);
    pcnt_65=100*sa_data(stat,total_65)/total_pop;
    pcnt_70=sa_data(stat,HH_70_79_pcnt)+sa_data(stat,HH_80_pcnt);
    if pcnt_65>0
        frac_70_among_old=min(pcnt_70/pcnt_65,1);
    else
        frac_70_among_old=0;
    end
    num_old_old=round(total_old_in_SA*frac_70_among_old);

    hh_with_1_old=find(stat_HH(:,4)==3);
    hh_with_2_old=find(stat_HH(:,4)==6);
    elderly_slots=[hh_with_1_old;hh_with_2_old;hh_with_2_old]; % 2nd elderly slot for 2-old HHs
    num_old_old=min(num_old_old,length(elderly_slots));
    old_old_idx=datasample(1:length(elderly_slots),num_old_old,'replace',false);
    old_old_rows=elderly_slots(old_old_idx);
    for r=1:length(old_old_rows)
        stat_HH(old_old_rows(r),6)=stat_HH(old_old_rows(r),6)+1;
    end

    % DATA = stat, HH ID, Individuals,  old, childrens, old_old_count
    HH_data=[HH_data;stat_HH];
    ind=ind+size(stat_HH,1);

end
HH_data( HH_data(:,3)==0,:)=[];
old_old_count=HH_data(:,[2,6]); % [HH_ID, old_old_count] -- keyed lookup, safe across later row deletions
HH_data=[HH_data(:,1:3),HH_data(:,5),HH_data(:,4)];

end