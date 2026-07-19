function weights=cal_weights(mu,sig,scale,x)
        y = normpdf(x,mu,sig);
        y1=normpdf(mu,mu,sig);
        
        weights=(y-y1/2)/scale;
        