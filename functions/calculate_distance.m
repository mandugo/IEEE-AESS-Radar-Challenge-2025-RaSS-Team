function [spatial_dist, time_dist] = calculate_distance(p1, p2)
% CALCULATE_DISTANCE - Calcola la distanza spaziale e temporale tra due punti tracciati
%
% Inputs:
%   p1, p2 : Vettori [range, angolo (°), velocità, tempo] (1x4)
%
% Outputs:
%   spatial_dist : Distanza euclidea nel piano range-angolo
%   time_dist    : Distanza temporale assoluta

    if ~isvector(p1) || ~isvector(p2) || numel(p1) < 4 || numel(p2) < 4
        error('Entrambi gli input devono essere vettori di almeno 4 elementi: [range, angolo, velocità, tempo].');
    end

    r1 = p1(1); a1 = p1(2); t1 = p1(4);
    r2 = p2(1); a2 = p2(2); t2 = p2(4);

    % --- Conversione polare → cartesiano ---
    x1 = r1 * cosd(a1);
    y1 = r1 * sind(a1);
    x2 = r2 * cosd(a2);
    y2 = r2 * sind(a2);

    % --- Calcolo distanza spaziale e temporale ---
    spatial_dist = hypot(x2 - x1, y2 - y1);  % distanza euclidea
    time_dist = abs(t2 - t1);                % distanza temporale
end
