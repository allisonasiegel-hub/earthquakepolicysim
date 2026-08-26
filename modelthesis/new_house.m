function [Assets,HH_data,Build_Data,LU,new_A,new_B,HH_change]=new_house(possible_assets,Assets,HH_data,Build_Data,FFF1,weight_pick,yo_exponent,oo_exponent)
% weight_pick (optional, default false): if true and this household is
% elderly (HH_data col5 >= 3), bias the pick toward higher-service
% buildings AMONG already-qualifying candidates instead of picking
% uniformly at random -- eligibility (who even qualifies) is unaffected,
% only which qualifying option gets picked. Old-old (col5==6) leans
% harder toward the top of the available range than young-old (col5==3)
% -- squaring/cubing a set of positive weights increases the relative
% gap between the best and worst options, so a higher exponent
% concentrates the pick more on the highest-service candidates.
% yo_exponent/oo_exponent (optional, default 1/2): exponent applied to
% the shifted-positive service-ratio weight for young-old/old-old.
% Modes 1-4 use the default 1/2 (linear/squared); mode 5 passes 2/3
% (squared/cubed) for a more aggressive building-level pull.
LU=[];
new_A=[];
new_B=[];
HH_change=[];
if nargin<7 || isempty(yo_exponent); yo_exponent=1; end
if nargin<8 || isempty(oo_exponent); oo_exponent=2; end
if size(possible_assets,1)>1
    ageGroup = HH_data(FFF1,5);
    if nargin>=6 && weight_pick && ageGroup>=3
        [~,locB] = ismember(possible_assets(:,2), Build_Data(:,1));
        cand_svc = zeros(size(possible_assets,1),1);
        valid = locB>0;
        cand_svc(valid) = Build_Data(locB(valid), 19);
        base_weight = cand_svc - min(cand_svc) + eps; % shift positive; avoid all-zero weights
        if ageGroup==6
            weights = base_weight.^oo_exponent; % old-old: lean harder toward the top
        else
            weights = base_weight.^yo_exponent; % young-old: milder lean
        end
        selected_A=datasample(possible_assets,1,'Weights',weights);
    else
        selected_A=datasample(possible_assets,1);
    end
else
    selected_A=(possible_assets);
end
if selected_A(3)>1
    Assets(Assets(:,3)==selected_A(3),11)=1; % mark assest as occupied
    Assets(Assets(:,3)==HH_data(FFF1,11),11)=0; % mark old assets empty
    new_A(:,4)=HH_data(FFF1,1);
    HH_data(FFF1,11)=selected_A(3); % change HH data to new assets
    HH_data(FFF1,10)=selected_A(2); % change HH data to new building
    % BUG FIX: SA (col 1) was never synced to the new asset's SA, so any
    % cross-SA move (via find_new_house_sa_score, used for same-yeshuv/
    % other-yeshuv relocations) silently kept the household's OLD SA on
    % record forever -- HH_MOVE_TRACK's Final_SA always equaled
    % Original_SA, every SA-level metric/map stayed blind to real
    % relocations, and who_is_moving.m kept evaluating these HH under
    % their stale original SA's move probability. Within-SA moves
    % (find_new_house_same_stat's primary pathway) are unaffected since
    % selected_A(1) already equals the current SA there.
    HH_data(FFF1,1)=selected_A(1); % sync SA to the new asset's SA
    new_A(:,1)=selected_A(3);
    new_A(:,2)=1;
    new_A(:,3)=selected_A(1);
    new_B=selected_A(2);
    HH_change=HH_data(FFF1,2);
    if Build_Data(Build_Data(:,1)==selected_A(2),3)==0
        Build_Data(Build_Data(:,1)==selected_A(2),3)=1; % change building land use
        LU=selected_A(2); % changed land use    
    end
end