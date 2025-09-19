# Available Functions

- [extract_targets](#extract_targets): identifies and extracts **radar targets** from a detection map. It performs **detection, angle estimation (DOA), and SNR validation** to return the most relevant targets.
- [update_tracks](#update_tracks): maintains and updates a set of **object tracks** based on new incoming points. It decides whether a new point belongs to an existing track or if it should start a new one.  
---

# `extract_targets`

The `extract_targets` function identifies and extracts **radar targets** from a detection map.  
It performs **peak detection, angle estimation (DOA), and SNR validation** to return the most relevant targets.

## Inputs
- **detection_map**: 2D matrix where nonzero values indicate potential detections.  
- **noise_map**: 2D matrix estimating noise power at each range–Doppler bin.  
- **RD1, RD2**: Complex Range–Doppler maps from two antenna channels (used for angle estimation).  
- **d**: Normalized spacing between antennas (in wavelengths).  
- **max_targets**: Maximum number of targets to extract.  
- **area_min**: Minimum region size (to filter out spurious small detections).  

## Output
- **targets**: A matrix with rows of the form: [angle_deg, range_idx, doppler_idx, peak_val]
- **angle_deg**: Estimated angle of arrival (in degrees).  
- **range_idx**: Index in the range dimension.  
- **doppler_idx**: Index in the Doppler dimension.  
- **peak_val**: Detection strength (magnitude).  

## Processing Steps

1. **Input Validation**  
 Ensures all inputs are valid (matrices have the same size, parameters are positive scalars, etc.).

2. **Small Region Filtering**  
 - Calls `filter_small_regions` to remove clusters in the detection map smaller than `area_min`.  
 - This avoids noise spikes being treated as real targets.  

3. **Iterative Peak Extraction (up to `max_targets`)**
 - Find the **highest peak** in the detection map (`temp_map`).  
 - If no peak remains (`peak_val == 0`), stop.  
 - Get its coordinates (`v_idx`, `r_idx`).  

4. **Angle Estimation (DOA)**
 - Extract small patches (`span = 2`) around the peak from **RD1** and **RD2**.  
 - Compute the **phase difference** between channels.  

5. **SNR Validation (_optional_)**
 - Compare the peak value against the **noise level** (`noise_map`).  
 - Use `is_valid_detection(peak_val, local_noise, 10)` to enforce a minimum SNR threshold (here, 10 dB).  
 - If valid → add `[angle_deg, r_idx, v_idx, peak_val]` to the targets list.  

6. **Blanking Around the Peak**
 - To avoid detecting the same target multiple times, **zero out** a neighborhood around the detected peak (`±10 bins`).  

7. **Repeat**  
 - Continue until `max_targets` are extracted or no peaks remain.  

## Summary
- The function extracts **up to `max_targets` detections** from the radar map.  
- Each detection is validated for **region size** and **SNR**.  
- It estimates **angle of arrival** using **phase difference between antennas**.  
- After each detection, it suppresses nearby bins to avoid duplicates.  

---

# `update_tracks`

The `update_tracks` function maintains and updates a set of **object tracks** based on new incoming points.  
It decides whether a new point belongs to an existing track or if it should start a new one.  

## Inputs
- **tracks**: A cell array of tracks, where each track is a matrix of points (rows = time steps, columns = coordinates + time).  
- **new_point**: The new observation (e.g., `[x, y, t]`) to be assigned to a track.  
- **spatial_thresh**: Maximum spatial distance allowed to associate `new_point` with an existing track.  
- **time_thresh**: Maximum temporal distance allowed to associate `new_point` with an existing track.  
- **max_history**: Maximum number of points to keep per track (older points are removed).  

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

## Summary
- **Associates** the new point with the nearest valid track (spatially and temporally).  
- **Starts a new track** if no match is found.  
- **Limits track length** by keeping only the most recent `max_history` points.  

---
