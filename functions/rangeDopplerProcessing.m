function [RD1, RD2] = rangeDopplerProcessing(ch1, ch2, range_fft_size, doppler_fft_size)
% RANGEDOPPLERPROCESSING  Compute Range-Doppler maps from raw channel data.
%
%   [RD1, RD2] = RANGEDOPPLERPROCESSING(ch1, ch2, range_fft_size, doppler_fft_size)
%
%   Computes windowed FFTs along range and Doppler dimensions for each channel.
%   Hann windows are applied automatically along both dimensions.
%
%   Inputs:
%       ch1              - [NxM] matrix of channel 1 time-domain data
%       ch2              - [NxM] matrix of channel 2 time-domain data
%       range_fft_size   - FFT size for range processing (columns)
%       doppler_fft_size - FFT size for Doppler processing (rows)
%
%   Outputs:
%       RD1 - Range-Doppler map from channel 1 (fftshifted in Doppler)
%       RD2 - Range-Doppler map from channel 2 (fftshifted in Doppler)

    % Validate input sizes
    if ~isequal(size(ch1), size(ch2))
        error('ch1 and ch2 must be of equal size.');
    end

    [N_chirps, N_samples] = size(ch1);

    % Range window (Hann)
    range_window = hann(N_samples).';
    ch1 = ch1 .* range_window;
    ch2 = ch2 .* range_window;

    % Range FFT
    R1 = fft(ch1, range_fft_size, 2);
    R2 = fft(ch2, range_fft_size, 2);
    R1 = R1(:, 1:range_fft_size/2);
    R2 = R2(:, 1:range_fft_size/2);

    % Doppler window (Hann)
    doppler_window = hann(N_chirps);
    R1 = R1 .* doppler_window;
    R2 = R2 .* doppler_window;

    % Doppler FFT and shift
    RD1 = fftshift(ifft(R1, doppler_fft_size, 1), 1);
    RD2 = fftshift(ifft(R2, doppler_fft_size, 1), 1);
end
