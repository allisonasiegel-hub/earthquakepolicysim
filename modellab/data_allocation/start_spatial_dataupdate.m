function start_spatial_data(floor_hight,file,working_stat,WS,unit_size_scale)
% unit_size_scale (optional, default 1): multiplies the per-SA synthetic
% dwelling-unit size distribution (mean and std) before carving each
% building's floorspace into units. A building's total floorspace is
% fixed (real survey data); this only changes how many units it gets
% divided into -- >1 means fewer, larger units per building, which
% directly controls city-wide vacancy rate (unit count) vs. real household
% count (fixed, census-driven). Ported from modelthesis's identical fix
% (data_allocation/start_spatial_dataupdate.m, run_regenerate_tveria_fix.m) -
% confirmed there that 1.7806 brings vacancy from ~48% down to ~10% for the
% Tiberias tveria-corrected building file - re-derive this factor for
% modellab's own household/building counts if they differ enough to matter.
if nargin<5 || isempty(unit_size_scale); unit_size_scale=1; end
%% combine assets data with deal data
%% read data 
[Assets,~,Assets_p1]=xlsread([file,'assets_B7_Final.csv']);
[dealData,~,dealData_p1]=xlsread([file,'dealdataB7.csv']);

%% get the last deal data
Deal_data=sortrows(dealData,[2,-3]);

%% coonect deal data to assest
[locA,locB]=ismember(Assets(:,1),Deal_data(:,2));
locB(locB==0)=[];
Assets(locA,5:10)=Deal_data(locB,:);
Assets_P=[Assets_p1(1,:),dealData_p1(1,:)];

% clearvars -except Assets_P Assets file floor_hight file

%% load buildings
[Build_Data,Build_Data_p,~]=xlsread([file,'bldgs_height_tt.csv']);
Build_Data(Build_Data(:,5) == 0,:) = [];

[locA,~]=ismember(Assets(:,2),Build_Data(:,1));
Assets = Assets(locA,:);

%% work only on one area
% if WS==1
%     STAT_W=working_stat;
%     locA=ismember(Build_Data(:,4),STAT_W);
%     Build_Data=Build_Data(locA,:);
% else
%     STAT_W=unique(Build_Data(:,4));    
% end
%% find usage - function
Build_Data=find_usage(Build_Data,file);

%% connect buildings to assests
for i=1:size(Build_Data,1)
    B_id=Build_Data(i,1);
    ass=Assets(Assets(:,2)==B_id,:);
    if size(ass,1)>0
        res_code=mode(ass(ass(:,9)>0,9));
        YEAR=ass(:,3);
        YEAR(YEAR<1800)=[];
        Build_Data(i,10)=nanmean(YEAR);
        if res_code>1
            Build_Data(i,3)=res_code;
        end
    end
    Assets(Assets(:,2)==B_id,9)=Build_Data(i,3);
    Assets(Assets(:,2)==B_id,11)=Build_Data(i,4);
end
Assets_P=[Assets_P,'stat'];
%% work only on one stat
% locA=ismember(Assets(:,11),STAT_W);
% Assets=Assets(locA,:);

Build_Data(Build_Data(:,10)==0,10)=nan;
Build_Data_p=[Build_Data_p,'year'];
%% delete unrelevant stat
% Build_Data(Build_Data(:,6)< 700000,:)=[];

%% assets mean price and size
%% now for each stat area calculate - many times missing data!
stat=unique(Assets(:,11));
for i=1:length(stat)
    
    A_data=Assets(Assets(:,11)==stat(i),:);
    A_data(A_data(:,5)==0,:)=[];
    price_m=nanmedian(A_data(:,10));
    price_std=nanstd(A_data(:,10))/sqrt(size(A_data,1));
    area_m=nanmedian(A_data(:,8));
    area_std=nanstd(A_data(:,8))/sqrt(size(A_data,1));
    assets_data(i,:)=[stat(i),price_m,price_std,area_m,area_std];
    
end
assets_data_P=['stat','price_m','price_std','area_m','area_std'];
% clearvars -except assets_data Build_Data Build_Data_p assets_data_P floor_hight

%% if missing data - fill by other data
P=sum(assets_data(:,3)==0);
Mean=nanmean(assets_data(assets_data(:,3)~=0,2:5));
assets_data(assets_data(:,3)==0,2:5)=repmat(Mean,P,1);
P=find((isnan(assets_data)));
[r,c]=ind2sub(size(assets_data),P);
ur=unique(r);
assets_data(ur,2:5)=repmat(Mean,length(ur),1);

%% create artificial assets
ind=1; % assets ind
stat=unique(Build_Data(:,4));
X=100;Assets=[];

Problem_st=[];
for i=1:length(stat)
    stat_Build_Data=Build_Data(Build_Data(:,4)==stat(i),:);
    %if hight is missing
    stat_Build_Data(isnan(stat_Build_Data(:,2)),2)=nanmean(stat_Build_Data(:,2));
    ass_data=assets_data(assets_data(:,1)==stat(i),:);
    if isempty(ass_data)
        ass_data=[stat(i),Mean];
        Problem_st=[Problem_st;stat(i)];
    end
    sintetic_asset_size=normrnd(ass_data(4)*unit_size_scale,ass_data(5)*unit_size_scale,[size(stat_Build_Data,1)*X,1]);
    sintetic_asset_size(sintetic_asset_size<30)=[];
    sintetic_asset_price=normrnd(ass_data(2),ass_data(3),[size(stat_Build_Data,1)*X,1]);
    sintetic_asset_price(sintetic_asset_price<(ass_data(2)-ass_data(3)))=mean(sintetic_asset_price);
    sintetic_asset_price(sintetic_asset_price<(ass_data(2)-ass_data(3)))=[];
    for j=1:size(stat_Build_Data,1)
        if stat_Build_Data(j,3)==1
            bui_AREA=ceil(stat_Build_Data(j,2)/floor_hight)*stat_Build_Data(j,7);
            FLOORS=ceil(stat_Build_Data(j,2)/floor_hight);
            Build_Data(Build_Data(:,1)==stat_Build_Data(j,1),11)=FLOORS;
            if bui_AREA<30
                Build_Data(Build_Data(:,1)==stat_Build_Data(j,1),3)=2;
            end
            C=cumsum(sintetic_asset_size);
            F=find(C>bui_AREA,1,'first')-1;
            if size(F,1)>0 && size(sintetic_asset_price,1)>F
                H=sum(sintetic_asset_size(1:F));
                building_ass=[ones(F,1).*stat(i),ones(F,1).*stat_Build_Data(j,1),(ind:ind+F-1)',sintetic_asset_size(1:F),sintetic_asset_price(1:F)];
                ind=ind+F;
                extra=bui_AREA-H;
                if extra>30
                   building_ass=[building_ass;[stat(i),stat_Build_Data(j,1),ind,extra,sintetic_asset_price(F+1)]];
                   ind=ind+1;
                   sintetic_asset_price(1)=[];                
                end
                sintetic_asset_price(1:F)=[];
                sintetic_asset_size(1:F)=[];
                Assets=[Assets;building_ass];
                building_ass=[];
            else
                building_ass=[building_ass;[stat(i),stat_Build_Data(j,1),ind,bui_AREA,nanmean(sintetic_asset_price)]];
                ind=ind+1;
                if ~isempty(sintetic_asset_price)
                    sintetic_asset_price(1)=[];
                else
                    warning('sintetic_asset_price is already empty, skipping deletion.');
                end
               Assets=[Assets;building_ass];
               building_ass=[];
            end
        else
            FLOORS=stat_Build_Data(j,2)/floor_hight;
            Build_Data(Build_Data(:,1)==stat_Build_Data(j,1),11)=FLOORS;
        end
    end
end

Assets_P={'stat','Building_id','id,','area_m','price M'};
% clearvars -except Build_Data Build_Data_p Assets Assets_P file 'sa_data.csv'

%% if stat cannot be for living
[sa,sa_P]=xlsread([file,'sa_data_B7.csv']);
ind=sa(sa(:,46)>1,1);
[locA,locB]=ismember(Build_Data(:,4),ind);
Build_Data(locA,3)=5;
sa(locB(locB>0),45);
Build_Data_p=[Build_Data_p,'floors'];
if WS ==1
    locA=ismember(Build_Data(:,4),working_stat);
    Build_Data=Build_Data(locA,:);
    locA=ismember(Assets(:,1),working_stat);
    Assets=Assets(locA,:);
end
clearvars -except Build_Data Build_Data_p Assets Assets_P

save('buildings&assets.mat')

