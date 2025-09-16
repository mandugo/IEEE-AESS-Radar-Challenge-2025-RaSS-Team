function updateVisualization(RD, targets, tracks, handles, t_now, md_matrix)
% UPDATEVISUALIZATION  Aggiorna i plot con i dati del frame corrente.

    % === Stati persistenti (creati una sola volta) ===
    persistent last_range last_angle md_vmax_ewma ...
               pol_lines pol_mark ang_lines ang_pts hInfo MAXL
    if isempty(MAXL), MAXL = 6; end   % tracce max visualizzate (regolabile)

    if isempty(last_range)
        last_range = nan; last_angle = nan;
    end

    % Precrea linee su POLAR
    if isempty(pol_lines) || any(~isgraphics(pol_lines))
        hold(handles.pax,'on');
        pol_lines = gobjects(MAXL,1);
        pol_mark  = gobjects(MAXL,1);
        for i = 1:MAXL
            pol_lines(i) = polarplot(handles.pax, nan, nan, '-', ...
                'Color',[0 1 0 0.85], 'LineWidth',2.0, 'Tag','trk_line');
            pol_mark(i)  = polarplot(handles.pax, nan, nan, 'wx', ...
                'MarkerSize',8, 'LineWidth',1.5, 'Tag','trk_mark');
        end
        hold(handles.pax,'off');
        pol_markers = pol_mark; %#ok<NASGU>
    end

    % Precrea linee su ANGLE vs TIME
    if isempty(ang_lines) || any(~isgraphics(ang_lines))
        hold(handles.ax_ang,'on');
        ang_lines = gobjects(MAXL,1);
        ang_pts   = gobjects(MAXL,1);
        for i = 1:MAXL
            ang_lines(i) = plot(handles.ax_ang, nan, nan, '-', ...
                'Color',[0 1 0 0.85], 'LineWidth',1.5, 'Tag','ang_line');
            ang_pts(i)   = plot(handles.ax_ang, nan, nan, 'wo', ...
                'MarkerSize',4, 'MarkerFaceColor','w', 'Tag','ang_pt');
        end
        hold(handles.ax_ang,'off');
    end

    % Precrea/ottieni textbox info (mostra/nascondi, non ricreare)
    if isempty(hInfo) || ~isgraphics(hInfo)
        hInfo = annotation(handles.fig, 'textbox', [0.8, 0.12, 0.07, 0.3], ...
            'String','-- WAITING FOR TARGET --', 'Color','w', 'BackgroundColor','k', ...
            'EdgeColor','#00D000', 'LineWidth', 1.5, 'FitBoxToText','on', ...
            'FontName','Consolas', 'FontSize',10, 'Visible','off', 'Tag','info_text_box');
    end

    % === RD Map ===
    set(handles.rd_map, 'CData', RD');
    set(handles.rd_title, 'String', sprintf('RD Map', t_now));

    ranges     = handles.rd_map.YData;
    velocities = handles.rd_map.XData;

    if ~isempty(targets) && size(targets,2) >= 3 && any(all(isfinite(targets(:,1:3)),2))
        set(handles.rd_markers, ...
            'XData', velocities(targets(:,3)), ...
            'YData', ranges(targets(:,2)));
    else
        set(handles.rd_markers, 'XData', nan, 'YData', nan);
    end

    % === POLAR: aggiorna linee (niente delete/ricrea) ===
    ntrk = min(numel(tracks), MAXL);
    for i = 1:ntrk
        tr = tracks{i};
        if size(tr,1) >= 2
            tr_s = (size(tr,1) >= 5) .* movmean(tr,5,1) + (size(tr,1) < 5).*tr; %#ok<NASGU>
            if size(tr,1) >= 5
                tr_s = movmean(tr,5,1);
            else
                tr_s = tr;
            end
            th = deg2rad(tr_s(:,2));
            rr = tr_s(:,1);
            set(pol_lines(i), 'ThetaData', th, 'RData', rr, 'Visible','on');
            set(pol_mark(i),  'ThetaData', th(end), 'RData', rr(end), 'Visible','on');
        else
            set(pol_lines(i), 'ThetaData', nan, 'RData', nan, 'Visible','off');
            set(pol_mark(i),  'ThetaData', nan, 'RData', nan, 'Visible','off');
        end
    end
    % nascondi linee in eccesso
    for i = ntrk+1:MAXL
        set(pol_lines(i), 'ThetaData', nan, 'RData', nan, 'Visible','off');
        set(pol_mark(i),  'ThetaData', nan, 'RData', nan, 'Visible','off');
    end

    % === Info box + marker veloci ===
    has_targets = ~isempty(targets) && size(targets,2) >= 3 && any(all(isfinite(targets(:,1:3)),2));
    if has_targets
        target_velocities = velocities(targets(:,3));
        [~, ord] = sort(abs(target_velocities), 'descend');
        sorted_targets = targets(ord, :);

        info_str = cell(0,1);
        for i = 1:size(sorted_targets,1)
            curr = sorted_targets(i,:);
            info_str{end+1} = sprintf('-- Target %d (%.2f m/s) --', i, velocities(curr(3)));
            info_str{end+1} = sprintf('  Range: %.2f m', ranges(curr(2)));
            info_str{end+1} = sprintf('  Angle: %.1f°', curr(1));
            if i < size(sorted_targets, 1), info_str{end+1} = ' '; end
        end
        set(hInfo, 'String', info_str, 'Visible','on');

        fastest_target = sorted_targets(1,:);
        last_range = ranges(fastest_target(2));
        last_angle = fastest_target(1);
    else
        set(hInfo, 'Visible','off');
        last_range = nan; last_angle = nan;
    end

    % === ANGLE over TIME: riusa linee preallocate ===
    for i = 1:ntrk
        tr = tracks{i};
        if size(tr,1) >= 2
            tt = tr(:,4); aa = tr(:,2);
            if numel(tt) >= 5, tt = movmean(tt,3); aa = movmean(aa,3); end
            set(ang_lines(i), 'XData', tt, 'YData', aa, 'Visible','on');
            set(ang_pts(i),   'XData', tt(end), 'YData', aa(end), 'Visible','on');
        else
            set(ang_lines(i), 'XData', nan, 'YData', nan, 'Visible','off');
            set(ang_pts(i),   'XData', nan, 'YData', nan, 'Visible','off');
        end
    end
    for i = ntrk+1:MAXL
        set(ang_lines(i), 'XData', nan, 'YData', nan, 'Visible','off');
        set(ang_pts(i),   'XData', nan, 'YData', nan, 'Visible','off');
    end

    % === MICRO-DOPPLER: smoothing leggero + dB + CLim dinamico ===
    K = [1 2 1; 2 4 2; 1 2 1];  K = K / sum(K(:));
    mask    = isfinite(md_matrix);
    md_fill = md_matrix;  md_fill(~mask) = 0;
    num     = conv2(md_fill, double(K), 'same');
    den     = conv2(double(mask), double(K), 'same');
    md_smooth = num ./ max(den, eps);

    md_db = 10*log10(md_smooth + 1e-12);

    finite_vals = md_db(isfinite(md_db));
    if isempty(finite_vals), finite_vals = -120; end
    cur_vmax = max(finite_vals);
    if isempty(md_vmax_ewma) || ~isfinite(md_vmax_ewma)
        md_vmax_ewma = cur_vmax;
    else
        md_vmax_ewma = 0.95*md_vmax_ewma + 0.05*cur_vmax;
    end
    dyn_range = 40;
    set(handles.ax_md, 'CLim', [md_vmax_ewma - dyn_range, md_vmax_ewma]);

    set(handles.md_map, 'CData', md_db, 'AlphaData', isfinite(md_db));

    zln = findobj(handles.ax_md, 'Tag','md_zero_line');
    if isempty(zln)
        yline(handles.ax_md, 0, '-', 'Color', [1 1 1 0.25], ...
              'LineWidth', 1, 'Tag','md_zero_line');
    end

    % === AXIS SYNC (tempo) ===
    f_eff = find(any(isfinite(md_matrix),1), 1, 'last'); if isempty(f_eff), f_eff = 1; end
    if isfield(handles,'md_t_frame') && ~isempty(handles.md_t_frame) && handles.md_t_frame > 0
        dt = handles.md_t_frame;
    elseif f_eff > 1
        dt = t_now / (f_eff - 1);
    else
        dt = max(t_now, eps);
    end
    t_end_full = (size(md_matrix,2) - 1) * dt;
    t_end_eff  = (f_eff - 1) * dt;
    x_end = max(t_end_eff, eps);

    set(handles.md_map, 'XData', [0, t_end_full]);   % mapping lineare colonne->tempo
    set(handles.ax_md,  'XLim', [0, x_end]);         % aggiorna ogni frame
    if isfield(handles,'ax_ang') && isgraphics(handles.ax_ang)
        set(handles.ax_ang, 'XLim', [0, x_end]);     % sincronizza angle vs time
    end

    % === VIDEO (precaricato) – sync con tempo radar ===
    if isfield(handles,'video') && isfield(handles.video,'frames') ...
            && ~isempty(handles.video.frames) && isgraphics(handles.ax_vid) && isgraphics(handles.vid_im)
    
        % Tempo radar dal numero di colonne utili della MD (più affidabile di t_now)
        f_eff = find(any(isfinite(md_matrix),1), 1, 'last'); if isempty(f_eff), f_eff = 1; end
        if isfield(handles,'md_t_frame') && ~isempty(handles.md_t_frame) && handles.md_t_frame > 0
            t_radar = (f_eff - 1) * handles.md_t_frame;
        else
            t_radar = t_now;   % fallback
        end
    
        % Offset e speed opzionali (mettili in plot_handles.video.t0/.speed nel main)
        t0  = 0;   if isfield(handles.video,'t0')    && ~isempty(handles.video.t0),    t0  = handles.video.t0;    end
        spd = 1.0; if isfield(handles.video,'speed') && ~isempty(handles.video.speed), spd = handles.video.speed; end
    
        times = handles.video.times;
        fps   = handles.video.fps;
    
        % Target time nel video
        t_target = t0 + spd * t_radar;
        t_target = min(max(times(1), t_target), times(end));       % clamp
    
        % Frame nearest (indicizzazione 1-based)
        [~, idx] = min(abs(times - t_target));
        idx = max(1, min(idx, numel(handles.video.frames)));
    
        frame = handles.video.frames{idx};
    
        % Flip opzionali (se vuoi forzarli da main: plot_handles.video.flipud = true; ecc.)
        if isfield(handles.video,'flipud')  && handles.video.flipud,  frame = flipud(frame);  end
        if isfield(handles.video,'fliplr')  && handles.video.fliplr,  frame = fliplr(frame);  end
    
        set(handles.vid_im, 'CData', frame);
        title(handles.ax_vid, sprintf('Ground-truth video', times(idx)), 'Color','w');
    end

end
