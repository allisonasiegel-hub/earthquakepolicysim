function [X, Y] = wgs84_to_itm(lat, lon)
% WGS84_TO_ITM  Convert WGS84 lat/lon (degrees) to Israeli Transverse
% Mercator (ITM, EPSG:2039) X/Y (meters), matching the coordinate system
% Build_Data(:,5)/(:,6) use in this codebase's *.mat datasets.
%
% Standard Snyder (1987) transverse Mercator forward series, GRS80
% ellipsoid, official ITM projection parameters (Israel Survey of Israel):
%   lat0 = 31 44 03.817 N = 31.7343936111 deg
%   lon0 = 35 12 16.261 E = 35.2045169444 deg
%   k0   = 1.0000067
%   False Easting  = 219529.584 m
%   False Northing = 626907.390 m
% lat/lon accepted as column or row vectors (degrees); X/Y returned in
% the same shape.

a = 6378137.0;
f = 1/298.257222101;
e2 = f*(2-f);
e4 = e2^2;
e6 = e2^3;
ep2 = e2/(1-e2); % second eccentricity squared

lat0 = 31.7343936111 * pi/180;
lon0 = 35.2045169444 * pi/180;
k0 = 1.0000067;
FE = 219529.584;
FN = 626907.390;

phi = lat(:) * pi/180;
lam = lon(:) * pi/180;

Mfun = @(p) a*((1 - e2/4 - 3*e4/64 - 5*e6/256)*p ...
             - (3*e2/8 + 3*e4/32 + 45*e6/1024)*sin(2*p) ...
             + (15*e4/256 + 45*e6/1024)*sin(4*p) ...
             - (35*e6/3072)*sin(6*p));

M0 = Mfun(lat0);
M = Mfun(phi);

N = a ./ sqrt(1 - e2*sin(phi).^2);
T = tan(phi).^2;
C = e2*cos(phi).^2/(1-e2);
A = (lam - lon0) .* cos(phi);

X = k0*N.*(A + (1-T+C).*A.^3/6 + (5 - 18*T + T.^2 + 72*C - 58*ep2).*A.^5/120) + FE;
Y = k0*(M - M0 + N.*tan(phi).*(A.^2/2 + (5-T+9*C+4*C.^2).*A.^4/24 + (61-58*T+T.^2+600*C-330*ep2).*A.^6/720)) + FN;

X = reshape(X, size(lat));
Y = reshape(Y, size(lat));
end
