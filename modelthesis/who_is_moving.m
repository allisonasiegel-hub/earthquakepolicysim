function moving_HH=who_is_moving(HH_data,random_number,unique_stat,intra_SA,K,eld_movef)
    SH=size(HH_data,1);
    R=datasample(random_number,SH); % random number ; 4 times the size of HH
    MM=zeros(SH,1); % zero vector size as HH matrix
    elderly = HH_data(:,5)>=2;


    for u=1:length(unique_stat) 
      intra_SA_data = intra_SA(intra_SA(:,1)==unique_stat(u),K); % K={2,3,4} - 'intraSAProb'; matching SA ID

      if size(intra_SA_data,1) > 1
          intra_SA_data = nanmean(intra_SA_data); % avarage probability
      end

      % BUG FIX: intraSAProb/intraYeshuvProb/interYeshuvProb are annual
      % rates (same source/convention as inOutRatio, which migration_19.m
      % correctly divides by 365) but were being used here as a raw
      % per-step probability -- ~365x too high. Confirmed against real
      % census data (growthrates1.xlsx): the model's raw intraYeshuvProb
      % (3-9%) is close in magnitude to the real ANNUAL within-settlement
      % between-SA leaving rate (2-5.5%), not a daily one.
      intra_SA_data = intra_SA_data/365;

      move_prob = intra_SA_data * ones(SH,1);

      move_prob(elderly) = ...
        move_prob(elderly) * eld_movef;

      M = HH_data(:,1)==unique_stat(u) & R<move_prob;

      MM=MM+M; % Append

    end
    moving_HH=HH_data(MM>0,2); % store all random HH ID ready for moving




