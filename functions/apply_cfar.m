function [detection_map, noise_map] = apply_cfar(mag_data, guard_r, guard_d, train_r, train_d, Pfa)
% APPLY_CFAR  Applies CA-CFAR (Cell Averaging) detection on a Range-Doppler map.
%
%   [detection_map, noise_map] = APPLY_CFAR(mag_data, guard_r, guard_d, train_r, train_d, Pfa)
%
%   Inputs:
%       mag_data     - Magnitude map (e.g., |RD|), size [Nd x Nr]
%       guard_r      - Number of guard cells in range
%       guard_d      - Number of guard cells in Doppler
%       train_r      - Number of training cells in range
%       train_d      - Number of training cells in Doppler
%       Pfa          - Desired false alarm rate (e.g., 1e-5)
%
%   Outputs:
%       detection_map - Map with detections (same size as mag_data)
%       noise_map     - Estimated noise level at each cell

    if nargin < 6
        error('apply_cfar:MissingInputs', 'All six input arguments are required.');
    end
    if ~ismatrix(mag_data)
        error('mag_data must be a 2D matrix.');
    end
    if any([guard_r, guard_d, train_r, train_d] < 0) || ...
       ~all(fix([guard_r, guard_d, train_r, train_d]) == [guard_r, guard_d, train_r, train_d])
        error('Guard and training cell values must be non-negative integers.');
    end
    if ~isscalar(Pfa) || Pfa <= 0 || Pfa >= 1
        error('Pfa must be a scalar in the range (0, 1).');
    end

    [Nd, Nr] = size(mag_data);
    cfar_mask = false(Nd, Nr);
    noise_map = nan(Nd, Nr);  % Initialize noise threshold map

    win_d = guard_d + train_d;
    win_r = guard_r + train_r;

    % Total number of training cells
    N_train = (2*train_d + 2*guard_d + 1) * (2*train_r + 2*guard_r + 1) ...
            - (2*guard_d + 1)*(2*guard_r + 1);

    if N_train <= 0
        error('Number of training cells must be positive.');
    end

    % CA-CFAR threshold scaling factor
    alpha = N_train * (Pfa^(-1/N_train) - 1);

    % Optional masking of close range artifacts
    % mag_data(:, 1:25) = 0;

    % --- CFAR processing loop ---
    for i = 1+win_d : Nd-win_d
        for j = 1+win_r : Nr-win_r
            CUT = mag_data(i, j);

            % Extract local window
            local = mag_data(i-win_d:i+win_d, j-win_r:j+win_r);

            % Exclude guard cells and CUT
            local((win_d-guard_d+1):(win_d+guard_d+1), ...
                  (win_r-guard_r+1):(win_r+guard_r+1)) = NaN;

            noise_cells = local(~isnan(local));

            if isempty(noise_cells)
                continue;  % skip if not enough training cells
            end

            % Noise estimation (CA-CFAR)
            noise_est = mean(noise_cells);
            threshold = alpha * noise_est;

            noise_map(i, j) = noise_est;

            if CUT > threshold
                cfar_mask(i, j) = true;
            end
        end
    end

    % Output detection map
    detection_map = zeros(size(mag_data));
    detection_map(cfar_mask) = mag_data(cfar_mask);
end
