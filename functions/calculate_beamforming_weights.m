function weights = calculate_beamforming_weights(null_angle_deg, d, disable_nulling)
% CALCULATE_BEAMFORMING_WEIGHTS  Compute 2-element beamforming weights for null steering.
%
%   weights = CALCULATE_BEAMFORMING_WEIGHTS(null_angle_deg, d, disable_nulling)
%
%   Inputs:
%       null_angle_deg   - Direction (in degrees) where the null is steered
%       d                - Spacing between elements (in wavelengths)
%       disable_nulling  - (optional) If true, returns uniform weights [1; 1]
%
%   Output:
%       weights          - [2x1] complex weight vector (unit-norm)

    if nargin < 3
        disable_nulling = true;
    end

    if disable_nulling
        weights = [1; 1];
        return;
    end

    null_angle_rad = deg2rad(null_angle_deg);
    phase_shift = -2 * pi * d * sin(null_angle_rad);

    weights = [1; -exp(1j * phase_shift)];
    weights = weights / norm(weights);
end
