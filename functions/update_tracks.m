function tracks = update_tracks(tracks, new_point, spatial_thresh, time_thresh, max_history)

best_idx = -1;
min_dist = inf;

for i = 1:length(tracks)
    track = tracks{i};
    if isempty(track)
        continue;
    end
    last_point = track(end, :);
    [dist_space, dist_time] = calculate_distance(last_point, new_point);
    if dist_space < spatial_thresh && dist_time < time_thresh && dist_space < min_dist
        min_dist = dist_space;
        best_idx = i;
    end
end

if best_idx > 0
    tracks{best_idx}(end+1, :) = new_point;
    if size(tracks{best_idx}, 1) > max_history
        tracks{best_idx}(1, :) = [];
    end
else
    tracks{end+1} = new_point;
end
end
