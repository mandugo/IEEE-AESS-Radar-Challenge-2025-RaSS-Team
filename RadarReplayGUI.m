function RadarReplayGUI()
% RadarReplayGUI - Interactive GUI for radar replay, tracking, micro-doppler and video sync
% This GUI wraps the processing and visualization logic into a single app.
% It reproduces the 2x3 layout: RD | Video (spanning two); Angle/Time | Micro-Doppler | Polar.
%
% Requirements:
% - Functions in `functions/`: apply_cfar, calculate_beamforming_weights, clutterRemoval,
%   extract_targets, rangeDopplerProcessing, update_tracks, setupVisualization, updateVisualization
% - Radar .mat file with variable `data` sized [num_frames x 2 x num_chirps x num_samples]
%
% Usage:
%   >> RadarReplayGUI

	%addpath(fullfile(pwd, 'functions'));

	app = struct();

	% === Default Radar Parameters (modifiable via code or by editing below) ===
	app.params.num_chirps   = 64;
	app.params.ramp_time_us = 500;           % chirp duration [us]
	app.params.sample_rate  = 0.6e6;         % [Hz]
	app.params.chirp_bw     = 400e6;         % [Hz]
	app.params.fc           = 10.2e9;        % [Hz]
	app.params.c            = 3e8;           % [m/s]
	app.params.lambda       = app.params.c / app.params.fc;
	app.params.d_lambda     = 2;             % antenna spacing in wavelengths

	% Derived
	app.params.ramp_time_s  = app.params.ramp_time_us * 1e-6;
	app.params.slope        = app.params.chirp_bw / app.params.ramp_time_s; % Hz/s
	app.params.range_fft_sz = [];   % filled after radar is loaded (depends on Ns)
	app.params.doppler_fft_sz = 2 * app.params.num_chirps;

	% Display/processing defaults
	app.display.R_MAX               = 25;    % meters
	app.display.colormap_levels     = 32;
	app.display.Pfa                 = 1e-4;
	app.display.guard_r             = 5;    app.display.guard_d = 5;
	app.display.train_r             = 15;   app.display.train_d = 15;
	app.display.apply_clutter       = true;
	app.display.bypass_nulling      = true;
	app.display.null_angle_deg      = 8.4;
	app.display.r_win               = 10;   % half-window for MD gaussian average
	app.display.alpha_idx           = 0.7;  % smoothing factor for range-bin selection

	% Video defaults
	app.video.path   = '';
	app.video.t0     = 0.0;   % seconds offset video vs radar (+ means video delayed)
	app.video.speed  = 2.7;   % video speed factor vs radar time
	app.video.frames = {};
	app.video.times  = [];
	app.video.fps    = [];
	app.video.flipud = false;
	app.video.fliplr = false;

	% State
	app.state.has_radar     = false;
	app.state.num_frames    = 0;
	app.state.current_frame = 1;
	app.state.tracks        = {};
	app.state.MAX_HISTORY   = 1000;
	app.state.SPATIAL_THRESHOLD = 2.0;
	app.state.TIME_THRESHOLD    = 2.0;
	app.state.weights        = [1; 1];
	app.state.global_max_amp = 1;
	app.state.last_range_idx = [];
	app.state.md_matrix      = [];
	app.state.timer          = [];
	app.state.isProcessing   = false;
	app.state.loop           = false;
	app.state.shouldStop     = false;

	% Build colormap
	app.display.colormap = buildGreenColormap(app.display.colormap_levels);

	% Placeholder axes setup using default theoretical axes; will be updated after loading radar
	[app.axes.velocities_ms, app.axes.ranges_m] = computeAxesForDefaults(app);
	[app.axes.ranges_use, app.axes.R_MAX_BIN] = clampRanges(app.axes.ranges_m, app.display.R_MAX);

	% Create main visualization figure and axes
	app.plot = setupVisualization(app.axes.velocities_ms, app.axes.ranges_use, app.display.colormap, app.display.R_MAX);

	% Reserve a control panel at the bottom of the main figure
	app.ui.panel = uipanel('Parent', app.plot.fig, 'Units','normalized', 'Position',[0.02 0.03 0.2 0.94], ...
		'BackgroundColor','k', 'ForegroundColor','w', 'Title','Controls', 'HighlightColor',[0 1 0]);

	buildControls();
	updateWeights();

	% Store app in guidata for callbacks
	guidata(app.plot.fig, app);

	% on close, ensure timer is cleaned
	set(app.plot.fig, 'CloseRequestFcn', @onClose);

	% ===================== Nested helper functions =====================
	function cmap = buildGreenColormap(num_colors)
		g = linspace(0, 1, num_colors)'.^2;
		cmap = [zeros(num_colors,1), g, zeros(num_colors,1)];
	end

	function [velocities_ms, ranges_m] = computeAxesForDefaults(app)
		% Compute axes based on current parameters; range_fft_size depends on Ns after file load,
		% so we use a placeholder length for initial visualization that will be updated later.
		doppler_fft_size = 2 * app.params.num_chirps;
		PRI = app.params.ramp_time_s;
		df  = 1/(doppler_fft_size * PRI);
		doppler_freqs = (-floor(doppler_fft_size/2):ceil(doppler_fft_size/2)-1) * df;
		velocities_ms = doppler_freqs * app.params.lambda/2;

		% Placeholder range axis: use an arbitrary FFT size until radar data is loaded
		range_fft_size = 512;  % temporary; will be reset upon radar load
		beat_freqs = (0:range_fft_size/2 - 1) * app.params.sample_rate / range_fft_size;
		ranges_m   = beat_freqs * app.params.c / (2*app.params.slope) - 3;
	end

	function [ranges_use, R_MAX_BIN] = clampRanges(ranges_m, R_MAX)
		R_MAX_BIN = find(ranges_m <= R_MAX, 1, 'last');
		if isempty(R_MAX_BIN) || R_MAX_BIN < 2
			error('R_MAX too small: no usable range bin (R_MAX=%.2f m).', R_MAX);
		end
		ranges_use = ranges_m(1:R_MAX_BIN);
	end

	function buildControls()
		p = app.ui.panel;
		fg = [1 1 1]; bg = [0 0 0];
		common = {'Units','normalized','BackgroundColor',bg,'ForegroundColor',fg,'FontName','Consolas','FontSize',9};

		% Sidebar layout parameters (tighter vertical spacing)
		left = 0.06; right = 0.94; top = 0.955; lineH = 0.040; gap = 0.007; labelW = 0.40; ctrlW = 0.48;
		row = @(i) top - (i-1)*(lineH+gap);

		% Section: Files
		uicontrol(p, common{:}, 'Style','text', 'String','FILES', 'FontWeight','bold', 'Position',[left row(1)-0.005 0.9 lineH]);
		uicontrol(p, common{:}, 'Style','text', 'String','Radar MAT:', 'HorizontalAlignment','left', 'Position',[left row(2) labelW lineH]);
		app.ui.btnLoadRadar = uicontrol(p, common{:}, 'Style','pushbutton', 'String','Load...', 'Position',[right-ctrlW row(2) ctrlW lineH], 'Callback',@onLoadRadar, 'Tag','btnLoadRadar');
		uicontrol(p, common{:}, 'Style','text', 'String','Video:', 'HorizontalAlignment','left', 'Position',[left row(3) labelW lineH]);
		app.ui.btnLoadVideo = uicontrol(p, common{:}, 'Style','pushbutton', 'String','Load...', 'Position',[right-ctrlW row(3) ctrlW lineH], 'Callback',@onLoadVideo, 'Tag','btnLoadVideo');

		% Section: Playback
		uicontrol(p, common{:}, 'Style','text', 'String','PLAYBACK', 'FontWeight','bold', 'Position',[left row(5)+0.005 0.9 lineH]);
		app.ui.btnPlay = uicontrol(p, common{:}, 'Style','togglebutton', 'String','Play', 'Position',[left row(6) 0.42 lineH], 'Callback',@onPlayPause);
		app.ui.btnStop = uicontrol(p, common{:}, 'Style','pushbutton', 'String','Stop', 'Position',[left+0.46 row(6) 0.42 lineH], 'Callback',@onStop);
		app.ui.btnStep = uicontrol(p, common{:}, 'Style','pushbutton', 'String','Step >', 'Position',[left row(7) 0.42 lineH], 'Callback',@onStep);
		app.ui.chkLoop = uicontrol(p, common{:}, 'Style','checkbox', 'String','Loop', 'Position',[left+0.46 row(7) 0.42 lineH], 'Callback',@onToggleLoop, 'Value', app.state.loop);
		app.ui.lblStatus = uicontrol(p, common{:}, 'Style','text', 'String','Status: idle', 'HorizontalAlignment','left', 'Position',[left row(8) 0.90 lineH]);

		% Section: Processing
		uicontrol(p, common{:}, 'Style','text', 'String','PROCESSING', 'FontWeight','bold', 'Position',[left row(10)+0.005 0.9 lineH]);
		uicontrol(p, common{:}, 'Style','text', 'String','Range Max [m]:', 'HorizontalAlignment','left', 'Position',[left row(11) labelW lineH]);
		app.ui.editRmax = uicontrol(p, common{:}, 'Style','edit', 'String',num2str(app.display.R_MAX), 'Position',[right-ctrlW row(11) ctrlW lineH], 'Callback',@onChangeRmax);
		app.ui.chkBypass = uicontrol(p, common{:}, 'Style','checkbox', 'String','No Nulling', 'Position',[left row(12) labelW lineH], 'Callback',@onToggleBypassNull, 'Value', app.display.bypass_nulling);
		uicontrol(p, common{:}, 'Style','text', 'String','Null angle [deg]:', 'HorizontalAlignment','left', 'Position',[left row(13) labelW lineH]);
		app.ui.editNull = uicontrol(p, common{:}, 'Style','edit', 'String',num2str(app.display.null_angle_deg), 'Position',[right-ctrlW row(13) ctrlW lineH], 'Callback',@onChangeNullAngle);
		app.ui.chkClutter = uicontrol(p, common{:}, 'Style','checkbox', 'String','MTI', 'Position',[left row(14) labelW lineH], 'Callback',@onToggleClutter, 'Value', app.display.apply_clutter);
		uicontrol(p, common{:}, 'Style','text', 'String','CFAR Pfa:', 'HorizontalAlignment','left', 'Position',[left row(15) labelW lineH]);
		app.ui.editPfa = uicontrol(p, common{:}, 'Style','edit', 'String',num2str(app.display.Pfa), 'Position',[right-ctrlW row(15) ctrlW lineH], 'Callback',@onChangePfa);
		uicontrol(p, common{:}, 'Style','text', 'String','Gd/Tr (r,d):', 'HorizontalAlignment','left', 'Position',[left row(16) labelW lineH]);
		app.ui.editGdTr = uicontrol(p, common{:}, 'Style','edit', 'String',sprintf('%d,%d;%d,%d',app.display.guard_r,app.display.train_r,app.display.guard_d,app.display.train_d), 'Position',[right-ctrlW row(16) ctrlW lineH], 'Callback',@onChangeGdTr);

		% Section: Video options
		uicontrol(p, common{:}, 'Style','text', 'String','VIDEO OPTIONS', 'FontWeight','bold', 'Position',[left row(18)+0.005 0.9 lineH]);
		uicontrol(p, common{:}, 'Style','text', 'String','Video speed [x]:', 'HorizontalAlignment','left', 'Position',[left row(19) labelW lineH]);
		app.ui.editVspd = uicontrol(p, common{:}, 'Style','edit', 'String',num2str(app.video.speed), 'Position',[right-ctrlW row(19) ctrlW lineH], 'Callback',@onChangeVspeed);
		uicontrol(p, common{:}, 'Style','text', 'String','Video t0 [s]:', 'HorizontalAlignment','left', 'Position',[left row(20) labelW lineH]);
		app.ui.editVt0 = uicontrol(p, common{:}, 'Style','edit', 'String',num2str(app.video.t0), 'Position',[right-ctrlW row(20) ctrlW lineH], 'Callback',@onChangeVt0);
	end

	function updateWeights()
		if app.display.bypass_nulling
			null_angle = 0;
		else
			null_angle = app.display.null_angle_deg;
		end
		app.state.weights = calculate_beamforming_weights(null_angle, app.params.d_lambda, app.display.bypass_nulling);
		%title(app.plot.pax, sprintf('Range–Angle Traces (Polar) — null %.1f°', null_angle), 'Color','w');
	end

	function refreshAxesAfterRadarLoad()
		% Update RD and MD axes mapping to current velocities/ranges
		set(app.plot.rd_map, 'XData', app.axes.velocities_ms, 'YData', app.axes.ranges_use);
		set(app.plot.ax1, 'YLim', [0 app.display.R_MAX]);
        set(app.plot.pax, 'RLim', [0 app.display.R_MAX]);
        set(app.plot.pax.Children, 'RData', [0 app.display.R_MAX]);
		V = app.axes.velocities_ms(:);
		set(app.plot.md_map, 'YData', V);
		set(app.plot.ax_md, 'YLim', [min(V) max(V)]);

		% Update MD time mapping per column (one column = burst time)
		PRI = app.params.ramp_time_s;  % if idle exists, adjust accordingly
		md_t_frame = app.params.num_chirps * PRI;
		app.plot.md_t_frame = md_t_frame;
		set(app.plot.md_map, 'XData', [0 md_t_frame]);
		xlim(app.plot.ax_md, [0 md_t_frame]);
		linkaxes([app.plot.ax_ang, app.plot.ax_md], 'x');
	end

	function onLoadRadar(~, ~)
		[fn, fp] = uigetfile({'*.mat','MAT-files (*.mat)'}, 'Select radar data MAT');
		if isequal(fn,0), return; end
		S = load(fullfile(fp,fn), 'data');
		if ~isfield(S, 'data')
			uiwait(errordlg('Selected MAT does not contain variable "data".','Load error'));
			return;
		end

		app.state.data = S.data;
		app.state.num_frames = size(app.state.data, 1);
		app.state.current_frame = 1;
		app.state.tracks = {};
		app.state.global_max_amp = 1;
		app.state.last_range_idx = [];

		% Derive Ns from data and set FFT sizes like in main
		Ns = size(app.state.data, 4);
		n_range = floor(app.params.sample_rate * app.params.ramp_time_s * 0.9) - 1;
		n_range = min(n_range, Ns);
		app.params.range_fft_sz = 2 * n_range;

		% Axes
		beat_freqs   = (0:app.params.range_fft_sz/2 - 1) * app.params.sample_rate / app.params.range_fft_sz;
		ranges_m     = beat_freqs * app.params.c/(2*app.params.slope) - 3;
		doppler_fft_size = 2 * app.params.num_chirps;
		df           = 1/(doppler_fft_size * app.params.ramp_time_s);
		doppler_freqs= (-floor(doppler_fft_size/2):ceil(doppler_fft_size/2)-1) * df;
		velocities_ms= doppler_freqs * app.params.lambda/2;
		app.axes.velocities_ms = velocities_ms;
		app.axes.ranges_m      = ranges_m;
		[app.axes.ranges_use, app.axes.R_MAX_BIN] = clampRanges(ranges_m, app.display.R_MAX);

		% Pre-allocate MD matrix [Nv x F]
		app.state.md_matrix = nan(doppler_fft_size, app.state.num_frames);

		% Update visual axes mapping
		refreshAxesAfterRadarLoad();

		% Status
		set(app.ui.lblStatus, 'String', sprintf('Status: loaded radar %s — %d frames', fn, app.state.num_frames));
		set(app.ui.btnLoadRadar, 'String', 'Loaded', 'ForegroundColor', [0 1 0]);

		% Save
		guidata(app.plot.fig, app);
	end

	function onLoadVideo(~, ~)
		[fn, fp] = uigetfile({'*.mp4;*.avi;*.mov','Video files (*.mp4, *.avi, *.mov)'}, 'Select video file');
		if isequal(fn,0), return; end
		vp = fullfile(fp,fn);
		try
			vr = VideoReader(vp);
			fps = vr.FrameRate;
			Nf  = floor(vr.Duration * fps);
			frames = cell(Nf,1);
			for k = 1:Nf
				frames{k} = readFrame(vr);
			end
			video_times = (0:Nf-1)/fps;
			app.video.path   = vp;
			app.video.frames = frames;
			app.video.times  = video_times;
			app.video.fps    = fps;
			% inject into plot handles for updateVisualization consumption
			app.plot.video = struct('frames',{frames}, 'times',video_times, 'fps',fps, ...
				't0',app.video.t0, 'speed',app.video.speed, 'flipud',app.video.flipud, 'fliplr',app.video.fliplr);
			set(app.ui.lblStatus, 'String', sprintf('Status: loaded video %s (%d frames @ %.1f fps)', fn, Nf, fps));
			set(app.ui.btnLoadVideo, 'String', 'Loaded', 'ForegroundColor', [0 1 0]);
		catch ME
			uiwait(errordlg(sprintf('Failed to load video: %s', ME.message),'Video error'));
		end
		guidata(app.plot.fig, app);
	end

	function onChangeRmax(~, ~)
		val = str2double(get(app.ui.editRmax, 'String'));
		if ~isfinite(val) || val <= 0
			set(app.ui.editRmax, 'String', num2str(app.display.R_MAX));
			return;
		end
		app.display.R_MAX = val;
		if ~isempty(app.axes.ranges_m)
			[app.axes.ranges_use, app.axes.R_MAX_BIN] = clampRanges(app.axes.ranges_m, app.display.R_MAX);
			refreshAxesAfterRadarLoad();
		end
		guidata(app.plot.fig, app);
	end

	function onToggleBypassNull(~, ~)
		app.display.bypass_nulling = logical(get(app.ui.chkBypass, 'Value'));
		updateWeights();
		guidata(app.plot.fig, app);
	end

	function onChangeNullAngle(~, ~)
		val = str2double(get(app.ui.editNull, 'String'));
		if ~isfinite(val)
			set(app.ui.editNull, 'String', num2str(app.display.null_angle_deg));
			return;
		end
		app.display.null_angle_deg = val;
		updateWeights();
		guidata(app.plot.fig, app);
	end

	function onToggleClutter(~, ~)
		app.display.apply_clutter = logical(get(app.ui.chkClutter, 'Value'));
		guidata(app.plot.fig, app);
	end

	function onChangeVspeed(~, ~)
		val = str2double(get(app.ui.editVspd, 'String'));
		if ~isfinite(val) || val <= 0
			set(app.ui.editVspd, 'String', num2str(app.video.speed));
			return;
		end
		app.video.speed = val;
		if isfield(app.plot,'video') && ~isempty(app.plot.video)
			app.plot.video.speed = app.video.speed;
		end
		guidata(app.plot.fig, app);
	end

	function onChangeVt0(~, ~)
		val = str2double(get(app.ui.editVt0, 'String'));
		if ~isfinite(val)
			set(app.ui.editVt0, 'String', num2str(app.video.t0));
			return;
		end
		app.video.t0 = val;
		if isfield(app.plot,'video') && ~isempty(app.plot.video)
			app.plot.video.t0 = app.video.t0;
		end
		guidata(app.plot.fig, app);
	end

	function onToggleLoop(~, ~)
		app.state.loop = logical(get(app.ui.chkLoop, 'Value'));
		guidata(app.plot.fig, app);
	end

	function onChangePfa(~, ~)
		val = str2double(get(app.ui.editPfa, 'String'));
		if ~isfinite(val) || val <= 0 || val >= 1
			set(app.ui.editPfa, 'String', num2str(app.display.Pfa));
			return;
		end
		app.display.Pfa = val;
		guidata(app.plot.fig, app);
	end

	function onChangeGdTr(~, ~)
		str = strtrim(get(app.ui.editGdTr, 'String'));
		% Expect format "gr,tr;gd,td"
		try
			parts = sscanf(str, '%d,%d;%d,%d');
			if numel(parts) ~= 4, error('fmt'); end
			gr = parts(1); tr = parts(2); gd = parts(3); td = parts(4);
			if any([gr tr gd td] < 0)
				error('neg');
			end
			app.display.guard_r = gr; app.display.train_r = tr;
			app.display.guard_d = gd; app.display.train_d = td;
		catch
			set(app.ui.editGdTr, 'String', sprintf('%d,%d;%d,%d', app.display.guard_r, app.display.train_r, app.display.guard_d, app.display.train_d));
		end
		guidata(app.plot.fig, app);
    end

	function ensureTimer()
		if ~isempty(app.state.timer) && ~isvalid(app.state.timer)
			try
				stop(app.state.timer);
			catch
			end
			app.state.timer = [];
		end
		if isempty(app.state.timer) || ~isvalid(app.state.timer)
			app.state.timer = timer('ExecutionMode','fixedRate', 'BusyMode','drop', 'Period',0.033, 'TimerFcn',@onTick, 'ErrorFcn',@(~,e)disp(e));
			guidata(app.plot.fig, app);
		end
	end

	function startPlaybackTimer()
		% Always recreate a fresh timer to avoid stale state after pause/stop
		try
			if ~isempty(app.state.timer) && isvalid(app.state.timer)
				stop(app.state.timer);
				delete(app.state.timer);
			end
		except
		end
		app.state.timer = timer('ExecutionMode','fixedRate', 'BusyMode','drop', 'Period',0.033, 'TimerFcn',@onTick, 'ErrorFcn',@(~,e)disp(e));
		guidata(app.plot.fig, app);
		start(app.state.timer);
	end

	function onPlayPause(src, ~)
		% Refresh latest state
		app = guidata(app.plot.fig);
		if (~isfield(app,'state') || ~isfield(app.state,'data')) || isempty(app.state.data)
			uiwait(errordlg('Load radar data first.','No radar'));
			set(src, 'Value', 0);
			return;
		end
		ensureTimer();
		guidata(app.plot.fig, app);
		app = guidata(app.plot.fig);
		if get(src, 'Value') == 1
			% Start or resume
			set(src, 'String','Pause');
			app.state.shouldStop = false;
			app.state.isProcessing = false;
			guidata(app.plot.fig, app);
			if app.state.current_frame > app.state.num_frames
				app.state.current_frame = 1;
				app.state.tracks = {};
				app.state.global_max_amp = 1;
				app.state.last_range_idx = [];
				if ~isempty(app.state.md_matrix), app.state.md_matrix(:) = nan; end
				guidata(app.plot.fig, app);
			end
			startPlaybackTimer();
			app = guidata(app.plot.fig);
			set(app.ui.lblStatus, 'String', sprintf('Status: playing (frame %d/%d)', app.state.current_frame, app.state.num_frames));
		else
			set(src, 'String','Play');
			app.state.shouldStop = true;
			try
				if ~isempty(app.state.timer) && isvalid(app.state.timer)
					stop(app.state.timer);
					delete(app.state.timer);
				end
			catch
			end
			app.state.timer = [];
			guidata(app.plot.fig, app);
			set(app.ui.lblStatus, 'String', 'Status: paused');
		end
		guidata(app.plot.fig, app);
	end

	function onStop(~, ~)
		app.state.shouldStop = true;
		try
			if ~isempty(app.state.timer) && isvalid(app.state.timer)
				stop(app.state.timer);
				delete(app.state.timer);
			end
		catch
		end
		app.state.timer = [];
		set(app.ui.btnPlay, 'Value', 0, 'String','Play');
		app.state.current_frame = 1;
		app.state.tracks = {};
		app.state.global_max_amp = 1;
		app.state.last_range_idx = [];
		if ~isempty(app.state.md_matrix)
			app.state.md_matrix(:) = nan;
		end
		app.state.isProcessing = false;
		set(app.ui.lblStatus, 'String', 'Status: stopped');
		guidata(app.plot.fig, app);
	end

	function onStep(~, ~)
		if ~app.state.has_radar && (~isfield(app,'state') || ~isfield(app.state,'data'))
			uiwait(errordlg('Load radar data first.','No radar'));
			return;
		end
		onTick();
	end

	function onTick(~, ~)
		% Pull latest state (handles in callbacks may be stale if user changed GUI)
		app = guidata(app.plot.fig);
		% Reentrancy guard to avoid overlapped processing (can happen if callbacks are slow)
		if app.state.isProcessing
			return;
		end
		app.state.isProcessing = true;
		guidata(app.plot.fig, app);

		% Early stop/pause check
		if app.state.shouldStop
			app.state.isProcessing = false;
			guidata(app.plot.fig, app);
			return;
		end

		if app.state.current_frame > app.state.num_frames
			if app.state.loop && ~app.state.shouldStop
				app.state.current_frame = 1;
				app.state.tracks = {};
				app.state.global_max_amp = 1;
				app.state.last_range_idx = [];
				if ~isempty(app.state.md_matrix), app.state.md_matrix(:) = nan; end
				app.state.isProcessing = false;
				guidata(app.plot.fig, app);
			else
				if ~isempty(app.state.timer) && isvalid(app.state.timer)
					stop(app.state.timer);
				end
				set(app.ui.btnPlay, 'Value', 0, 'String','Play');
				set(app.ui.lblStatus, 'String', 'Status: finished');
				app.state.current_frame = 1;
				app.state.tracks = {};
				app.state.global_max_amp = 1;
				app.state.last_range_idx = [];
				if ~isempty(app.state.md_matrix)
					app.state.md_matrix(:) = nan;
				end
				app.state.isProcessing = false;
				guidata(app.plot.fig, app);
				return;
			end
		end

		f = app.state.current_frame;
		try
			% Extract bursts for each channel
			bursts_ch1 = squeeze(app.state.data(f, 1, :, :));
			bursts_ch2 = squeeze(app.state.data(f, 2, :, :));
			% Optional clutter removal
			if app.display.apply_clutter
				[ch1, ch2] = clutterRemoval(bursts_ch1, bursts_ch2, 'mti');
			else
				ch1 = bursts_ch1; ch2 = bursts_ch2;
			end
			% Range-Doppler per channel
			[RD1, RD2] = rangeDopplerProcessing(ch1, ch2, app.params.range_fft_sz, 2*app.params.num_chirps);
			% Limit to max range
			RD1 = RD1(:, 1:app.axes.R_MAX_BIN);
			RD2 = RD2(:, 1:app.axes.R_MAX_BIN);
			% 2-ch beamforming/nulling
			RD = app.state.weights(1)*RD1 + app.state.weights(2)*RD2;
			mag_avg = abs(RD);
			% CFAR
			[detection_map, noise_map] = apply_cfar(mag_avg, app.display.guard_r, app.display.guard_d, app.display.train_r, app.display.train_d, app.display.Pfa);
			% Micro-Doppler profile
			if isempty(app.state.last_range_idx), app.state.last_range_idx = round(size(RD,2)/2); end
			power_RD = abs(RD).^2;
			col_det  = sum(detection_map, 1);
			col_pow  = sum(power_RD, 1);
			if any(col_det)
				col_pow_n = col_pow ./ (max(col_pow) + eps);
				[~, best_idx] = max(col_det .* col_pow_n);
			else
				[~, best_idx] = max(col_pow);
			end
			smoothed_idx = round(app.display.alpha_idx*best_idx + (1-app.display.alpha_idx)*app.state.last_range_idx);
			smoothed_idx = max(1, min(size(RD,2), smoothed_idx));
			app.state.last_range_idx = smoothed_idx;
			% Gaussian weighting
			r0 = max(1, smoothed_idx - app.display.r_win);
			r1 = min(size(RD,2), smoothed_idx + app.display.r_win);
			cols  = r0:r1;
			sigma = max(0.8, app.display.r_win/1.5);
			w     = exp(-0.5 * ((cols - smoothed_idx)/sigma).^2);
			w     = w(:) / sum(w);
			PR             = power_RD(:, cols);
			micro_doppler  = PR * w;
			med_val        = median(micro_doppler, 'omitnan'); if ~isfinite(med_val), med_val = 0; end
			micro_doppler  = abs(micro_doppler - med_val);
			app.state.md_matrix(:, f) = micro_doppler;
			% Target extraction
			area_min = 4;  max_targets = 1;
			targets  = extract_targets(detection_map, noise_map, RD1, RD2, app.params.d_lambda, max_targets, area_min);
			% Global amplitude smoothing and dB normalization
			alpha_g   = 1;
			frame_max = max(abs(RD(:,25:end)),[],'all');
			app.state.global_max_amp = (1 - alpha_g)*app.state.global_max_amp + alpha_g*frame_max;
			RD_norm = 20*log10(abs(RD)/app.state.global_max_amp + 1e-12);
			% Tracking
			t_now = (f - 1) * (app.params.num_chirps * app.params.ramp_time_s);
			for i = 1:size(targets,1)
				angle    = targets(i,1);
				range_m  = app.axes.ranges_use(targets(i,2));
				velocity = app.axes.velocities_ms(targets(i,3));
				point    = [range_m, angle, velocity, t_now];
				app.state.tracks = update_tracks(app.state.tracks, point, app.state.SPATIAL_THRESHOLD, app.state.TIME_THRESHOLD, app.state.MAX_HISTORY);
			end
			% Inject video meta
			if ~isempty(app.video.frames)
				app.plot.video.frames = app.video.frames;
				app.plot.video.times  = app.video.times;
				app.plot.video.fps    = app.video.fps;
				app.plot.video.t0     = app.video.t0;
				app.plot.video.speed  = app.video.speed;
				app.plot.video.flipud = app.video.flipud;
				app.plot.video.fliplr = app.video.fliplr;
			end
			% Visualization
			updateVisualization(RD_norm, targets, app.state.tracks, app.plot, t_now, app.state.md_matrix);
			drawnow
			% Early stop/pause after UI callbacks
			if app.state.shouldStop
				app.state.isProcessing = false;
				guidata(app.plot.fig, app);
				return;
			end
			% Advance
			app.state.current_frame = app.state.current_frame + 1;
			app.state.has_radar = true;
			set(app.ui.lblStatus, 'String', sprintf('Status: playing (frame %d/%d)', min(app.state.current_frame, app.state.num_frames), app.state.num_frames));
		catch ME
			if ~isempty(app.state.timer) && isvalid(app.state.timer)
				stop(app.state.timer);
			end
			set(app.ui.btnPlay, 'Value', 0, 'String','Play');
			errordlg(sprintf('Processing error at frame %d: %s', f, ME.message), 'Processing error');
		end
		% Release reentrancy guard and push state
		app.state.isProcessing = false;
		guidata(app.plot.fig, app);
	end

	function onClose(~, ~)
		try
			if ~isempty(app.state.timer) && isvalid(app.state.timer)
				stop(app.state.timer);
				delete(app.state.timer);
			end
		catch
		end
		delete(app.plot.fig);
	end
end 