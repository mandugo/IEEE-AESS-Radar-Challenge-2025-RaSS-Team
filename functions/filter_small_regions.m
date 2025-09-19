function filtered_map = filter_small_regions(detection_map, area_min)
% FILTER_SMALL_REGIONS  Rimuove regioni con area inferiore a una soglia
%
%   filtered_map = FILTER_SMALL_REGIONS(detection_map, area_min)
%
%   Inputs:
%       detection_map - Mappa binaria o a valori reali (es. output CFAR)
%       area_min      - Area minima in pixel per mantenere una regione
%
%   Output:
%       filtered_map  - Mappa con le regioni troppo piccole rimosse

    if ~ismatrix(detection_map)
        error('detection_map deve essere una matrice 2D.');
    end
    if ~isscalar(area_min) || ~isnumeric(area_min) || area_min < 0
        error('area_min deve essere uno scalare numerico >= 0.');
    end

    % --- Rileva regioni connessi su mappa binaria ---
    bw = detection_map > 0;
    cc = bwconncomp(bw, 8);  % 8-connettività (include diagonali)
    stats = regionprops(cc, 'Area', 'PixelIdxList');

    % --- Rimuove le regioni troppo piccole ---
    filtered_map = detection_map;
    for k = 1:numel(stats)
        if stats(k).Area < area_min
            filtered_map(stats(k).PixelIdxList) = 0;
        end
    end
end
