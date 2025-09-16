function [ch1_clean, ch2_clean] = clutterRemoval(ch1, ch2, type, N)
% CLUTTERREMOVAL  Remove clutter from radar data using different strategies.
%
%   [ch1_clean, ch2_clean] = CLUTTERREMOVAL(ch1, ch2, type)
%   [ch1_clean, ch2_clean] = CLUTTERREMOVAL(ch1, ch2, type, N)
%
%   Inputs:
%       ch1   - [NxM] matrix, channel 1 data (N chirps x M range bins)
%       ch2   - [NxM] matrix, channel 2 data (same size as ch1)
%       type  - String specifying clutter removal method:
%                   'mti'     : First-order MTI via temporal difference
%                   'average' : Subtract mean clutter
%       N     - (Optional) Number of initial pulses for averaging (default: all)
%
%   Outputs:
%       ch1_clean - Clutter-reduced version of channel 1
%       ch2_clean - Clutter-reduced version of channel 2
%
%   Example:
%       [ch1_out, ch2_out] = clutterRemoval(ch1, ch2, 'average', 20);
%
%   See also: diff, mean

    % Validate inputs
    if nargin < 3
        error('Usage: clutterRemoval(ch1, ch2, type, [N])');
    end
    if ~ismatrix(ch1) || ~ismatrix(ch2)
        error('ch1 and ch2 must be 2D matrices.');
    end
    if ~isequal(size(ch1), size(ch2))
        error('ch1 and ch2 must have the same size.');
    end
    if nargin < 4 || isempty(N)
        N = size(ch1, 1);  % Use all pulses by default
    else
        N = min(N, size(ch1,1));  % Clip to max available pulses
    end

    % Perform selected clutter removal
    switch lower(type)
        case 'mti'
            ch1_clean = [zeros(1, size(ch1,2)); diff(ch1, 1, 1)];
            ch2_clean = [zeros(1, size(ch2,2)); diff(ch2, 1, 1)];

        case 'average'
            clutter1 = mean(ch1(1:N,:), 1);
            clutter2 = mean(ch2(1:N,:), 1);
            ch1_clean = ch1 - clutter1;
            ch2_clean = ch2 - clutter2;

        otherwise
            error('Unknown clutter removal type: "%s". Use "mti" or "average".', type);
    end
end
