function Assets = mean_price_per_meter(Assets)
stat = unique(Assets(:,1));
for i = 1:length(stat)
    mean_p = nanmean(Assets(Assets(:,1)==stat(i),5));
    Assets(Assets(:,1)==stat(i),5) = mean_p;
end