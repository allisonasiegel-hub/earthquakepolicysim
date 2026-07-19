function Individuals_data=set_Ind_data(DATA)
% HH_data = stat, HH ID, Individuals, childrens, old

U=unique(DATA(:,3));
U(U==1)=[];
U(isnan(U))=[];
individuals=[];

for i=1:length(U)
    ind=DATA(DATA(:,3)==U(i),:);
    ind_no_old=repmat(ind(ind(:,5)==0,:),U(i),1);
    ind_one_old=repmat(ind(ind(:,5)==3,:),U(i),1);
    ind_one_old(sum(ind(:,5)==3)+1:end,5)=0;
    ind_2_old=repmat(ind(ind(:,5)==6,:),U(i),1);
    ind_2_old(:,5)=3;
    
    individuals=[individuals;[ind_no_old; ind_one_old;ind_2_old]];
end
individuals=[individuals;DATA(DATA(:,3)==1,:)];

individuals(individuals(:,1)==0,:)=[];

individuals=sortrows( individuals,[2,5]); % sort according to HH and than by age
u=unique(individuals(:,3)); % family size

KID_DATA=[];
for i=1:length(u)
    kid_data=individuals(individuals(:,3)==u(i),:);
    k=unique(kid_data(:,4));
    for j=1:length(k)
        kid_data_j=kid_data(kid_data(:,4)==k(j),:);
        FS=[ones(k(j),1);zeros(u(i)-k(j),1)];
        FS=repmat(FS,[size(kid_data_j,1)/size(FS,1),1]);
        assert(size(FS,1)==size(kid_data_j,1));
        kid_data_j(FS==1,5)=1;
		assert(size(FS,1) == size(kid_data_j,1));
        KID_DATA=[KID_DATA;kid_data_j];
    end
end
Individuals_data= KID_DATA;
Individuals_data(Individuals_data(:,5)==0,5)=2;
