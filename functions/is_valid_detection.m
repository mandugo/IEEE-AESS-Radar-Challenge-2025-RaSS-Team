function is_valid = is_valid_detection(peak_value, noise_floor, min_snr_db)
% IS_VALID_DETECTION  Valuta se una detection ha un SNR sufficiente
%
%   is_valid = IS_VALID_DETECTION(peak_value, noise_floor, min_snr_db)
%
%   Inputs:
%       peak_value   - Valore del picco rilevato
%       noise_floor  - Stima del rumore locale
%       min_snr_db   - Soglia minima di SNR in dB (default: 12 dB)
%
%   Output:
%       is_valid     - true se il picco ha SNR sufficiente, false altrimenti

    % --- Default ---
    if nargin < 3
        min_snr_db = 12.0;
    end

    % --- Sanificazione input ---
    if ~isscalar(peak_value) || peak_value < 0
        error('peak_value must be a non-negative scalar.');
    end
    if ~isscalar(noise_floor) || noise_floor < 0
        error('noise_floor must be a non-negative scalar.');
    end
    if ~isscalar(min_snr_db) || min_snr_db < 0
        error('min_snr_db must be a non-negative scalar.');
    end

    % --- Calcolo SNR ---
    snr_linear = peak_value / (noise_floor + 1e-12);  % evita divisione per zero
    snr_db = 10 * log10(snr_linear);

    % --- Verifica soglia ---
    is_valid = snr_db >= min_snr_db;
end
