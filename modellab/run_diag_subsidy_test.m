city = 'Ashkelon';
shock_step = 40;
steps = 60;
n_sims = 1;
temp_dev_duration = Inf;
tempdev_patience_duration = 8;
subsidy_residents_mode = 5;
subsidy_businesses_mode = 2;

run('run_model_earthquake_shelteroverflow.m')
