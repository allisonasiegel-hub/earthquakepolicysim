function [destroyed_B_P, destroyed_B] = earth_quake(Build_Data, dmg_input)

    if nargin < 2 || isempty(dmg_input)
        error('earth_quake:MissingDamageTable', ...
              'Provide a damage table (filename, table, or Nx2 numeric).');
    end

    %--- normalize damage table to a MATLAB table with vars SAID,dmg_prc
    if ischar(dmg_input) || isstring(dmg_input)
        T = readtable(dmg_input);
    elseif istable(dmg_input)
        T = dmg_input;
    elseif isnumeric(dmg_input) && size(dmg_input,2) >= 2
        T = array2table(dmg_input(:,1:2), 'VariableNames', {'SAID','dmg_prc'});
    else
        error('earth_quake:BadDamageTable', ...
              'dmg_input must be filename, table with SAID/dmg_prc, or Nx2 numeric.');
    end

    % If names are not exactly SAID/dmg_prc, coerce first two columns
    if ~all(ismember({'SAID','dmg_prc'}, T.Properties.VariableNames))
        T = T(:,1:2);
        T.Properties.VariableNames = {'SAID','dmg_prc'};
    end

    % Ensure numeric
    T.SAID    = double(T.SAID);
    T.dmg_prc = double(T.dmg_prc);

    % Collapse potential duplicate SAID rows by taking the max percentage
    [uniqSA, ~, g] = unique(T.SAID);
    dmgPrc = accumarray(g, T.dmg_prc, [], @max);

    % Coerce percentages: if >1, treat as percent (e.g., 6 -> 0.06)
    dmgPrc(dmgPrc > 1) = dmgPrc(dmgPrc > 1) / 100;
    % Clamp to [0,1]
    dmgPrc = max(0, min(1, dmgPrc));

    nB = size(Build_Data,1);
    damagedMask = false(nB,1);

    % For each SA, randomly mark the requested share of buildings as destroyed
    for i = 1:numel(uniqSA)
        said = uniqSA(i);
        p    = dmgPrc(i);
        if p <= 0, continue; end

        idx = find(Build_Data(:,4) == said);
        if isempty(idx), continue; end

        k = round(p * numel(idx));
        k = min(max(k,0), numel(idx));
        if k == 0, continue; end

        sel = idx(randperm(numel(idx), k)); % random buildings within this SA
        damagedMask(sel) = true;
    end

    % Build outputs (keep your original fields/definitions)
    destroyed_B_P = {'building ID','recovery time','size'};

    ids  = Build_Data(damagedMask, 1);
    rect = zeros(nnz(damagedMask), 1); % recovery time initialized to 0
    sz   = Build_Data(damagedMask, 7) .* ceil(Build_Data(damagedMask, 11)); % area * floors

    destroyed_B = [ids, rect, sz];

end
