function g = hh_age_group(HH_data, rows)
%HH_AGE_GROUP  Household age group: 0 = non-elderly, 1 = young-old, 2 = old-old.
%
%   g = hh_age_group(HH_data)        one entry per household in HH_data
%   g = hh_age_group(HH_data, rows)  only the given row indices
%
%   Single source of truth for the elderly age split. TWO INDEPENDENT
%   HH_data columns are involved and must not be confused:
%
%     col 5  = 3 * (number of members aged 65+), i.e. 0 / 3 / 6.
%              A HEADCOUNT of elderly members, NOT an age band. Set in
%              data_allocation/create_HH_12_2018.m, whose own comment
%              reads "3->1 elderly, 6->2 elderly".
%     col 12 = number of members aged 70+, i.e. 0 / 1 / 2. Attached in
%              data_allocation/distribute_HH_2019.m and labelled
%              'number of old-old (70+)' in HH_data_P.
%
%   Reading col5==3 as young-old and col5==6 as old-old is WRONG: it
%   splits households by how many elderly members they have, not by age.
%   On data_for_model_tmine_agesplit70.mat that misclassifies 1452 of
%   3978 elderly households (36%) -- 1067 households holding a 70+
%   member are coded 3, and 385 households with nobody over 70 are
%   coded 6.
%
%   Old-old takes priority: a household with >=1 member aged 70+ is
%   old-old; an elderly household with no 70+ member is young-old. This
%   matches the convention already used in pref_hh.m and SA_score_old.m.
%
%   Datasets built before the age split have no col 12; there every
%   elderly household is reported as young-old (group 1).

if nargin < 2 || isempty(rows)
    rows = (1:size(HH_data,1))';
end
rows = rows(:);

elderly = HH_data(rows,5) >= 2; % col5 is 0/3/6, so >=2 selects 3 and 6

if size(HH_data,2) >= 12
    old_old = HH_data(rows,12) >= 1;
else
    old_old = false(numel(rows),1);
end

g = zeros(numel(rows),1);
g(elderly)           = 1;
g(elderly & old_old) = 2;
end
