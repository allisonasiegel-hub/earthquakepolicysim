function HH_destroyed=shock_H(HH_data,Assets)
loca=ismember(HH_data(:,11),Assets(:,3)); % locate all HH by ID
HH_destroyed=HH_data(loca==0,2); % all destroyed HH