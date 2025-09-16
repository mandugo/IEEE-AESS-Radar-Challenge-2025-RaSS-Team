# `update_tracks`

The `update_tracks` function maintains and updates a set of **object tracks** based on new incoming points.  
It decides whether a new point belongs to an existing track or if it should start a new one.  

---

## Inputs
- **tracks**: A cell array of tracks, where each track is a matrix of points (rows = time steps, columns = coordinates + time).  
- **new_point**: The new observation (e.g., `[x, y, t]`) to be assigned to a track.  
- **spatial_thresh**: Maximum spatial distance allowed to associate `new_point` with an existing track.  
- **time_thresh**: Maximum temporal distance allowed to associate `new_point` with an existing track.  
- **max_history**: Maximum number of points to keep per track (older points are removed).  

---

## Mechanism

1. **Initialization**
   - Set `best_idx = -1` (no track selected yet).  
   - Set `min_dist = inf` (to find the closest match).  

2. **Search for Candidate Track**
   - Loop through all existing tracks.  
   - Skip empty tracks.  
   - Extract the **last point** of the track.  
   - Compute **spatial** and **temporal** distances between the last point and `new_point` (via `calculate_distance`).  
   - If both distances are below their thresholds **and** the spatial distance is the smallest so far, update `best_idx`.  

3. **Update or Create Track**
   - If a valid `best_idx` is found:
     - Append `new_point` to the corresponding track.  
     - If the track length exceeds `max_history`, remove the oldest point (FIFO).  
   - If no suitable track is found:
     - Start a **new track** containing only `new_point`.  

---

## Behavior Summary
- **Associates** the new point with the nearest valid track (spatially and temporally).  
- **Starts a new track** if no match is found.  
- **Limits track length** by keeping only the most recent `max_history` points.  

---

✅ In short:  
The function is a **data association mechanism** for tracking, deciding whether a new observation extends an existing trajectory or starts a new one.
