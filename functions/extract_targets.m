function targets = extract_targets(detection_map, noise_map, RD1, RD2, d, max_targets, area_min)
% EXTRACT_TARGETS  Estrae target dalla detection map con stima DOA e SNR check
%
%   targets = EXTRACT_TARGETS(detection_map, noise_map, RD1, RD2, d, max_targets, area_min)
%
%   Inputs:
%       detection_map - Mappa di rilevazione (valori > 0)
%       noise_map     - Mappa di stima del rumore
%       RD1, RD2      - Mappe Range-Doppler complesse dei due canali
%       d             - Spaziatura normalizzata tra le antenne
%       max_targets   - Numero massimo di target da estrarre
%       area_min      - Area minima per regione valida
%
%   Output:
%       targets       - Matrice [angle_deg, range_idx, doppler_idx, peak_val]

    if ~ismatrix(detection_map) || ~ismatrix(noise_map)
        error('detection_map e noise_map devono essere matrici 2D.');
    end
    if ~isequal(size(detection_map), size(noise_map), size(RD1), size(RD2))
        error('Tutte le mappe devono avere le stesse dimensioni.');
    end
    if ~isscalar(d) || ~isnumeric(d) || d <= 0
        error('d deve essere uno scalare positivo.');
    end
    if ~isscalar(max_targets) || max_targets < 1
        error('max_targets deve essere uno scalare positivo.');
    end
    if ~isscalar(area_min) || area_min < 0
        error('area_min deve essere uno scalare non negativo.');
    end

    % --- Rimozione regioni troppo piccole ---
    temp_map = filter_small_regions(detection_map, area_min);
    span = 2;
    targets = [];

    % --- Estrazione picchi ---
    for t = 1:max_targets
        [peak_val, idx] = max(temp_map(:));
        if peak_val == 0, break; end
        [v_idx, r_idx] = ind2sub(size(temp_map), idx);

        % Calcolo angolo
        if v_idx > span && v_idx + span <= size(RD1, 1) && ...
           r_idx > span && r_idx + span <= size(RD1, 2)

            patch1 = angle(RD1(v_idx-span:v_idx+span, r_idx-span:r_idx+span));
            patch2 = angle(RD2(v_idx-span:v_idx+span, r_idx-span:r_idx+span));
            phase_diff = median(patch2(:) - patch1(:));
            phase_diff = mod(phase_diff + pi, 2*pi) - pi;
            ratio = min(max(phase_diff / (2*pi*d), -1), 1);
            angle_rad = asin(ratio);
            angle_deg = rad2deg(angle_rad);
        else
            angle_deg = 0;
        end

        % Validazione SNR
        local_noise = noise_map(v_idx, r_idx);
        if is_valid_detection(peak_val, local_noise, 10)
            targets = [targets; angle_deg, r_idx, v_idx, peak_val];
        end

        % Blanking intorno al picco
        mask_w = 10;
        v1 = max(1, v_idx - mask_w);
        v2 = min(size(temp_map,1), v_idx + mask_w);
        r1 = max(1, r_idx - mask_w);
        r2 = min(size(temp_map,2), r_idx + mask_w);
        temp_map(v1:v2, r1:r2) = 0;
    end
end
