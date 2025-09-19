%% 8‑Element Linear Array – Scan + Video Recording (0° → 180°)
% This script creates an MP4 video named 'array_scan.mp4' that shows a
% continuous scan of a uniform 8‑element linear array.  The video is
% written frame‑by‑frame during the animation loop.

clear all 
close all
clc

N      = 8;
lambda = 1;
d      = lambda/2;
k      = 2*pi/lambda;

scanDeg   = -90:0.5:90;
scanRad   = deg2rad(scanDeg);

plotDeg   = -90:0.5:90;
plotRad   = deg2rad(plotDeg);

AFmagAll = zeros(numel(scanRad), numel(plotRad));

for ii = 1:numel(scanRad)
    theta0 = scanRad(ii);
    AF   = sum( exp(1j * k * d * (0:N-1).' .* ...
                    (sin(plotRad)-sin(theta0))) );
    AFmagAll(ii,:) = abs(AF)/N;
end

vidFile   = 'array_scan.mp4';
v         = VideoWriter(vidFile,'MPEG-4');
v.FrameRate = 30;
open(v);

fig = figure('Name','8‑Element Array – Continuous Scan',...
             'NumberTitle','off', 'Color',[1 1 1]);

ax = polaraxes(fig);
grid(ax,'on');
rticks(ax,-40:5:0);
thetaticks(ax,0:30:180);
thetaticklabels(ax,{ '0°','30°','60°','90°','120°','150°','180°' });

ax.RLim = [0 1.2];
ax.ThetaZeroLocation = 'top';

for cycle = 1:1 
    for ii = 1:numel(scanRad)   % forward sweep (0 → 180)
        
        polarplot(ax, plotRad, AFmagAll(ii,:), 'LineWidth',2);
        rlim(ax,[0 1.2]); rticks(ax,-40:5:0);
        ax.ThetaZeroLocation = 'top';
        title(sprintf('Scanning -90° → 90°   θ₀ = %3.1f°',...
                      scanDeg(ii)));

        drawnow;
        pause(0.01);

        frame = getframe(fig);       % capture current screen content
        writeVideo(v, frame);
    end

    for ii = numel(scanRad):-1:1  % backward sweep (180 → 0)

        polarplot(ax, plotRad, AFmagAll(ii,:), 'LineWidth',2);
        rlim(ax,[0 1.2]); rticks(ax,-40:5:0);
        ax.ThetaZeroLocation = 'top';
        title(sprintf('Scanning 180° → 0°   θ₀ = %3.1f°',...
                      scanDeg(ii)));

        drawnow;
        pause(0.01);

        frame = getframe(fig);
        writeVideo(v, frame);
    end
end

close(v);
fprintf('Video written to "%s"\n', vidFile);
