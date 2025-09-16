function handles = setupVisualization(velocities, ranges, cmap, max_range, clim_range)
% SETUPVISUALIZATION – Layout 2x3:
% Top: RD (TL), Video (spanning TM+TR)
% Bottom: Angle vs Time (BL), Micro-Doppler (BM), Polar (BR)

    if nargin < 4 || isempty(max_range), max_range = 40; end
    if nargin < 5 || isempty(clim_range), clim_range = [-30, 0]; end

    handles.fig = figure('Name','Radar Challenge 2025','NumberTitle','off');
    set(handles.fig, 'Color', 'k', 'Position', [120, 60, 1500, 900]);

    % --- posizioni (x y w h) ---
    	% Switch to left-side control panel; shrink and shift plots right
	% 2x2 grid of plots to the right of the sidebar; video spans full width below
	gapX = 0.05;  x0 = 0.28;  wcol = 0.3;  hrow = 0.2;
	yTop = 0.72;  yBot = 0.43;  yVid = 0.05;  hVid = 0.30;   % larger video with generous gaps
	posRD  = [x0,                 yTop, wcol,           hrow];    % top-left
	posMD  = [x0 + wcol + gapX,   yTop, wcol,           hrow];    % top-right
	posANG = [x0,                 yBot, wcol,           hrow];    % bottom-left
	posPOL = [x0 + wcol + 2*gapX,   yBot, wcol,           hrow];    % bottom-right
	posVID = [x0,                 yVid, 2*wcol+gapX,    hVid];    % bottom spanning two columns

    % === RD Map (Top-Left) ===
    handles.ax1 = axes('Position', posRD);
    handles.rd_map = imagesc(handles.ax1, velocities, ranges, nan(numel(ranges), numel(velocities)));
    	set(handles.ax1, 'YDir', 'normal', 'Color','k');
	xlabel(handles.ax1,'Velocity [m/s]','Color','w');
	ylabel(handles.ax1,'Range [m]','Color','w');
	handles.rd_title = title(handles.ax1,'RD Map','Color','w','Units','normalized','Position',[0.5 1.02 0]);
    	set(handles.ax1,'XColor','w','YColor','w','GridColor','#00D000','GridAlpha',0.3,...
		'MinorGridColor','#008000','MinorGridAlpha',0.3); grid(handles.ax1,'on');
	colormap(handles.ax1, cmap); clim(handles.ax1, clim_range); ylim(handles.ax1, [0, max_range]);
	%cb = colorbar(handles.ax1); cb.Color='w'; cb.Label.String='Power (dB)'; cb.Label.Color='w';
	hold(handles.ax1,'on');
    handles.rd_markers = plot(handles.ax1, nan, nan, 'wx', 'MarkerSize',10, 'LineWidth',1.5);
    hold(handles.ax1,'off');

    	% === Video (Bottom, spanning 2 columns) ===
	handles.ax_vid = axes('Position', posVID);
	set(handles.ax_vid,'Color','k','YDir','reverse');  % evita capovolgimento
	axis(handles.ax_vid, 'off'); axis(handles.ax_vid, 'image');
	title(handles.ax_vid,'Ground-truth video','Color','w');
	handles.vid_im = image('Parent', handles.ax_vid, 'CData', zeros(1,1,3,'uint8')); % placeholder

    % === Angle vs Time (Bottom-Left) ===
    handles.ax_ang = axes('Position', posANG);
    	set(handles.ax_ang,'Color','k','XColor','w','YColor','w',...
		'GridColor','#00D000','GridAlpha',0.3,'MinorGridColor','#008000','MinorGridAlpha',0.3);
	grid(handles.ax_ang,'on');
	ylabel(handles.ax_ang,'Angle [deg]','Color','w');
    xlabel(handles.ax_ang,'Time [s]','Color','w');
	title(handles.ax_ang,'Angle over Time','Color','w','Units','normalized','Position',[0.5 1.08 0]);
    			xlim(handles.ax_ang,[0 1]); ylim(handles.ax_ang,[-30 30]);

    % === Micro-Doppler (Bottom-Mid) ===
    handles.ax_md = axes('Position', posMD);
    V = velocities(:);
    handles.md_map = imagesc(handles.ax_md, [0 1], V, nan(numel(V), 2));
    	set(handles.ax_md,'YDir','normal','Color','k');
	xlabel(handles.ax_md,'Time [s]','Color','w'); ylabel(handles.ax_md,'Velocity [m/s]','Color','w');
	colormap(handles.ax_md, cmap); clim(handles.ax_md, clim_range);
	xlim(handles.ax_md,[0 1]); ylim(handles.ax_md,[min(V) max(V)]);
	set(handles.ax_md,'XColor','w','YColor','w','GridColor','#00D000','GridAlpha',0.3,...
		'MinorGridColor','#008000','MinorGridAlpha',0.3); grid(handles.ax_md,'on');
    %cb_md = colorbar(handles.ax_md); cb_md.Color='w'; cb_md.Label.String='Power (dB)'; cb_md.Label.Color='w';
    	handles.md_title = title(handles.ax_md,'Velocity over Time','Color','w','Units','normalized','Position',[0.5 1.02 0]);

    % === Polar (Bottom-Right) ===
    handles.pax = polaraxes('Position', posPOL);
    	title(handles.pax,'Range–Angle Traces','Color','w','Units','normalized','Position',[0.5 1.15 0]);
    	set(handles.pax,'ThetaZeroLocation','top','Color','k',...
		'GridColor','#00D000','MinorGridColor','#008000','GridAlpha',0.3,...
		'RColor','w','ThetaColor','w', 'ThetaLim',[-45 45], 'RLim',[0 max_range]);
	% keep polar box compact but do not force equal units on t/v or angle/time
	p = get(handles.pax,'Position'); p(4) = min(p(3), p(4)); p(3) = p(4); set(handles.pax,'Position',p);
    grid(handles.pax,'on'); hold(handles.pax,'on');
    hpbw_deg = [-13, 13];
    for a = hpbw_deg
        polarplot(handles.pax, [deg2rad(a) deg2rad(a)], [0 max_range], '-.', 'Color',[1 1 1 0.3], 'LineWidth',1.0);
    end
    %arc_r = max_range*0.94; th = deg2rad(linspace(-13,13,50));
    %polarplot(handles.pax, th, arc_r*ones(size(th)), '--', 'Color',[1 1 1 0.5]);
    %polarplot(handles.pax, deg2rad(12),  arc_r, '<', 'Color',[1 1 1 0.7], 'MarkerSize',7);
    %polarplot(handles.pax, deg2rad(-12), arc_r, '>', 'Color',[1 1 1 0.7], 'MarkerSize',7);
    %text(handles.pax, 0, max_range*0.97, 'HPBW TX', 'Color',[1 1 1 0.7], 'FontSize',9, 'HorizontalAlignment','center');
    hold(handles.pax,'off');

    % Link X tra Angle e Micro-Doppler
    linkaxes([handles.ax_ang, handles.ax_md], 'x');
end
