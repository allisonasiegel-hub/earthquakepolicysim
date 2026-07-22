function [destroyed_B_P,destroyed_B]=rocket_attack2(Build_Data,total_hits)

fs_threshold= 75; % floorspace threshold
maxNbrs= 3;  % neighbors per cluster
maxDist= 15; % max distance to neighbors
M= size(Build_Data,1);

% Prepare outputs & state
destroyed_B_P= {'building ID','recovery time','floorspace'};
destroyed_B= zeros(0,3);
removed= false(M,1);
coords= Build_Data(:,5:6);

hits= 0;
while hits<total_hits
    avail= find(~removed); % pick one available building at random
    i= avail( randi(numel(avail)) );
    % small building hit as a cluster
    fs = Build_Data(i,25);
    if fs < fs_threshold
        smallIdx = avail(Build_Data(avail,25)<fs_threshold & avail~=i);
        if ~isempty(smallIdx)
            d= sqrt(sum((coords(smallIdx,:) - coords(i,:)).^2,2)); % compute distances
            valid= d <= maxDist; % closest neighbors
            cand= smallIdx(valid);
            d_c= d(valid);
            if ~isempty(cand)
                [~,ord]= sort(d_c);
                nbrs= cand(ord(1:min(maxNbrs,numel(ord)))); % pick the relevant neighbors
                group= [i; nbrs];
            else
                group= i;  % no neighbors
            end
        else
            group= i;
        end
    else
        group = i;
    end

    for b = group.'
        destroyed_B(end+1, :) = [ Build_Data(b,1), 0, Build_Data(b,25)]; % 'ID','recovery time','floorspace'
    end
    removed(group)= true;
    hits= hits+ 1;
end