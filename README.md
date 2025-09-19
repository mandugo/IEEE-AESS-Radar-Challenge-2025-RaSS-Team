# IEEE-AESS-Radar-Challenge-2025-RaSS-Team
**Interactive MATLAB GUI for radar replay, tracking & micro‑Doppler analysis**

> **Author:** RaSS Team  
> **Date:** 2025‑09‑15

---

## 📖 Overview
The `RadarReplayGUI` function implements an interactive MATLAB GUI for replaying and analyzing radar data with optional video synchronization. It provides visualization, target tracking, and micro-Doppler analysis in a multi-panel layout.


| Feature | Description |
|---------|-------------|
| **Range–Doppler & Beamforming** | Computes 2‑channel range‑doppler maps with optional clutter removal (MTI) and CFAR detection. |
| **Micro‑Doppler** | Generates a time‑frequency micro‑doppler profile for the strongest target in each frame. |
| **Target Tracking** | Maintains tracks across frames using spatial & temporal thresholds. |
| **Video Sync** | Loads an external video file (mp4/avi/mov) and syncs it to the radar timeline with adjustable speed / offset. |
| **Nulling** | User‑configurable null angle – useful for sidelobe suppression or look‑away direction. |

The GUI emulates a 2×3 layout:  
- **RD** (Range‑Doppler) & **Video** (spanning two panels)  
- **Angle/Time**, **Micro‑Doppler**, and **Polar** views

---

## 🛠 Prerequisites
| Item | Minimum Version |
|------|----------------|
| MATLAB® | R2020a or newer (works up to 2024b) |
| Image Processing Toolbox | Optional – for `VideoReader` and image display. |
| Signal Processing Toolbox | Optional – used for FFT & CFAR utilities (built‑ins are fine). |

No external packages or toolboxes are required beyond the default MATLAB installation.

---

## 🚀 Installation & Setup

```bash
git clone https://github.com/mandugo/IEEE-AESS-Radar-Challenge-2025-RaSS-Team/
cd IEEE-AESS-Radar-Challenge-2025-RaSS-Team
```

1. **Add helper functions** – The MATLAB GUI relies on a handful of helper scripts located in `functions/`.  
   ```matlab
   addpath(fullfile(pwd,'functions'));
   ```
2. **Run the GUI** – In MATLAB command window:

   ```matlab
   RadarReplayGUI
   ```

The script will automatically create the main figure, build all UI components and load the helper functions.

---

## 🎬 Usage

1. **Load radar data**  
   - Click **“Load…”** under *FILES → Radar MAT*  
   - Choose a `.mat` file that contains variable `data`.  
     Example structure: `size(data) = [num_frames, 2, num_chirps, ns]`.

2. **Load video (optional)**  
   - Click **“Load…”** under *VIDEOS*. Supported formats: `mp4`, `avi`, `mov`.  

3. **Playback controls** –  
   | Button | Action |
   |--------|--------|
   | **Play/Pause** | Toggle playback. When playing, frames advance automatically at ~30 fps (timer period 0.033 s). |
   | **Step >** | Advance one frame manually. |
   | **Stop** | Reset to the first frame and clear tracks. |
   | **Loop** | Enable/disable looping when reaching the last frame. |

4. **Adjust parameters** –  
   - Range max, CFAR guard/training cells, null angle, video speed / offset are all editable via their respective edit fields or checkboxes.  

5. **Visual inspection** –  
   - The *RD* panel shows range‑doppler power (log scale) with CFAR detections highlighted.  
   - The *Micro‑Doppler* panel shows the instantaneous velocity profile of the strongest target.  
   - The *Polar* panel displays a polar plot of range–velocity points with tracks overlaid.

---

## 🎛 Controls & Parameters

| Control | Default value | Description |
|---------|---------------|-------------|
| **Range Max [m]** | `25` | Truncates the display to this maximum range. |
| **Null angle [deg]** | `8.4` | Beamforming null direction (degrees). For no nulling or tick *No Nulling*. |
| **CFAR Pfa** | `1e‑4` | Desired false alarm probability. |
| **Gd/Tr (r,d)** | `15,15;5,5` | Guard & training cells for CFAR in range and doppler dimensions. |
| **Video speed [x]** | `2.7` | Video playback speed relative to radar time. |
| **Video t0 [s]** | `0.0` | Initial video offset (positive → video delayed). |

---

## 📦 Dependencies

All helper functions live in the `functions/` folder:

| Function | Purpose | File |
|----------|---------|------|
| `apply_cfar.m` | CFAR detection | `functions/` |
| `calculate_beamforming_weights.m` | Compute 2‑beam weights for nulling | `functions/` |
| `clutterRemoval.m` | MTI clutter removal | `functions/` |
| `extract_targets.m` | Extract target coordinates from detections | `functions/` |
| `rangeDopplerProcessing.m` | 2‑D FFT and range–doppler | `functions/` |
| `update_tracks.m` | Maintain track history | `functions/` |
| `setupVisualization.m`, `updateVisualization.m` | Build & refresh axes | `functions/` |

---

## 📄 License

MIT © 2025 RaSS Team. See `LICENSE` for details.
