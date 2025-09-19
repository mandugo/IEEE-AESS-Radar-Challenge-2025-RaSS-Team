import zmq
import numpy as np
import pyqtgraph as pg
from pyqtgraph.Qt import QtCore, QtWidgets
from scipy.signal import butter, lfilter
from scipy.signal import convolve2d
import colorsys
import time
from datetime import datetime
import os

"""
radar_gui.py
------------
Real-time radar processing and visualization client.

Connects to a ZeroMQ PUSH stream of complex64 IQ data (from PlutoSDR + CN0566),
performs range–Doppler and angle estimation, and displays results in a PyQtGraph GUI.

Features:
- Range–Doppler map with CFAR-like thresholding
- Angle estimation via phase difference between two channels
- Real-time track management (range, angle, velocity) with smoothing and legend
- Optional data acquisition and saving to .npy files
"""

# ─── Radar parameters ────────────────────────────────────────────
num_chirps     = 64
ramp_time_us   = 500           # µs
sample_rate    = 0.6e6          # Hz

# FFT parameters
RANGE_PAD_FACTOR = 2    # Amount of zero-padding for range FFT
DOPPLER_PAD_FACTOR = 2  # Amount of zero-padding for Doppler FFT


# Radar configuration
CHIRP_BW = 300e6              # Hz (bandwidth)
C = 3e8                       # Speed of light in m/s
frequency = 10e9              # Hz (center frequency)
wavelength = C / frequency    # m

# Array parameters
d = 2  # spacing between antennas in wavelengths 

# Derived timing for windowing
ramp_s = ramp_time_us * 1e-6
SLOPE = CHIRP_BW / ramp_s     # Hz/s
begin_offset_s = 0.1 * ramp_s
valid_window_s = ramp_s - begin_offset_s
good_ramp_samples = int(valid_window_s * sample_rate)-1

range_fft_size = good_ramp_samples * RANGE_PAD_FACTOR
doppler_fft_size = num_chirps * DOPPLER_PAD_FACTOR

# Calculate range axis with zero-padding
beat_freqs = np.fft.fftfreq(range_fft_size, 1/sample_rate)[:range_fft_size//2]
ranges_m = beat_freqs * C / (2 * SLOPE)

# Calculate velocity axis with zero-padding
T_obs = num_chirps * ramp_s
doppler_freqs = np.fft.fftshift(np.fft.fftfreq(doppler_fft_size, ramp_s))
velocities_ms = doppler_freqs * wavelength / 2  # m/s

# step between burst starts (half-sample corrected)
step = int(np.floor(ramp_s * sample_rate))

# compute index matrix
n      = np.arange(num_chirps)
starts = (begin_offset_s * sample_rate + n * step).astype(int)
cols   = np.arange(good_ramp_samples)
idx    = starts[:, None] + cols[None, :]

# Low-pass filter design (optional)
nyq = sample_rate / 2
b_lpf, a_lpf = butter(4, 100e3/nyq, btype='low')
def apply_lpf(x): return lfilter(b_lpf, a_lpf, x)

# High-pass filter for clutter cancellation
# Cut-off frequency: about 0.1 normalized frequency (adjust as needed)
# This will suppress targets with very low Doppler frequencies
b_hpf, a_hpf = butter(4, 0.25, btype='high')
def apply_clutter_cancellation(data):
    """Apply high-pass filter along slow-time (Doppler) dimension"""
    #return lfilter(b_hpf, a_hpf, data, axis=0)
    return data-np.mean(data, axis=0)

# ZeroMQ pull socket
ctx  = zmq.Context()
pull = ctx.socket(zmq.PULL)
pull.connect('tcp://phaser.local:5555')

# PyQtGraph setup
app = QtWidgets.QApplication([])
win = pg.GraphicsLayoutWidget(show=True, title="Radar Processing")
win.resize(1200, 600)  # Make window wider for two plots

# Range-Doppler plot (left)
rd_plot = win.addPlot(row=0, col=0, title="Range-Doppler Map")
rd_plot.setLabel('bottom', 'Range (m)')
rd_plot.setLabel('left', 'Velocity (m/s)')
rd_plot.setXRange(0, ranges_m[-1])

# Range-Angle plot (right)
ra_plot = win.addPlot(row=0, col=1, title="Range-Angle Map")
ra_plot.setLabel('bottom', 'Range (m)')
ra_plot.setLabel('left', 'Angle (deg)')
ra_plot.setYRange(-90, 90)  # Set angle range to ±90 degrees
ra_plot.setXRange(0, ranges_m[-1])
# Track plotting items for Range-Angle plot
MAX_HISTORY = 100  # Number of points to keep in history
MAX_TRACK_AGE = 100.0  # seconds before considering track as old
SMOOTHING_WINDOW = 5  # Number of points for moving average
SPATIAL_THRESHOLD = 2.0  # meters, threshold for spatial distance
TIME_THRESHOLD = 2.0  # seconds, threshold for temporal distance

# Create legend area for track information
legend_text = pg.TextItem(anchor=(0, 1))  # Anchor to top-right
ra_plot.addItem(legend_text)
legend_text.setPos(ranges_m[-100], 80)  # Position at top-right of plot

# List of tracks, each track is a list of [range, angle, velocity, timestamp] pairs
tracks = [[]]  # Start with one empty track
track_lines = []  # List to store PlotDataItem for each track
track_colors = []  # Store fixed colors for each track
next_track_id = 0  # Global track ID counter

# Color generation for tracks
def generate_track_color(track_id):
    """Generate distinct colors for different tracks using golden ratio"""
    golden_ratio = 0.618033988749895
    hue = (track_id * golden_ratio) % 1.0
    rgb = colorsys.hsv_to_rgb(hue, 0.9, 0.9)
    return [int(255*x) for x in rgb]

def rgb_to_hex(rgb):
    """Convert RGB values to hex color string"""
    return f"#{rgb[0]:02x}{rgb[1]:02x}{rgb[2]:02x}"

# Create initial track line
def create_track_line():
    global next_track_id
    color = generate_track_color(next_track_id)
    next_track_id += 1
    line = pg.PlotDataItem(pen=pg.mkPen(color, width=2), symbol='o', symbolSize=6)
    ra_plot.addItem(line)
    track_colors.append(color)
    return line

initial_line = create_track_line()
track_lines.append(initial_line)

def calculate_distance(point1, point2):
    """Calculate spatial and temporal distances between two points in range-angle-time space"""
    range1, angle1, _, time1 = point1  # Extract range, angle and timestamp
    range2, angle2, _, time2 = point2
    
    # Convert angles to radians for distance calculation
    angle1_rad = np.deg2rad(angle1)
    angle2_rad = np.deg2rad(angle2)
    
    # Calculate x-y coordinates
    x1 = range1 * np.cos(angle1_rad)
    y1 = range1 * np.sin(angle1_rad)
    x2 = range2 * np.cos(angle2_rad)
    y2 = range2 * np.sin(angle2_rad)
    
    # Calculate spatial distance
    spatial_dist = np.sqrt((x2-x1)**2 + (y2-y1)**2)
    
    # Calculate temporal distance (in seconds)
    time_dist = abs(time2 - time1)
    
    return spatial_dist, time_dist

# Create control panel
control_proxy = QtWidgets.QGraphicsProxyWidget()
control_widget = QtWidgets.QWidget()
control_layout = QtWidgets.QHBoxLayout()
control_widget.setLayout(control_layout)

# Add data acquisition control
is_acquiring = False  # Global flag for acquisition state
acquired_data = []    # List to store acquired data frames

def toggle_acquisition():
    global is_acquiring
    is_acquiring = not is_acquiring
    
    if is_acquiring:
        # Start new acquisition
        acquired_data.clear()
        acq_toggle.setText("Stop Acquisition")
        acq_toggle.setStyleSheet("background-color: #ff6b6b")  # Red when recording
    else:
        # Stop acquisition and save data
        if acquired_data:
            # Create timestamp for filename
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"radar_data_{timestamp}.npy"
            
            # Convert list of frames to numpy array
            data_array = np.array(acquired_data)
            
            # Save the data
            np.save(filename, data_array)
            print(f"Saved {len(acquired_data)} frames to {filename}")
            
            # Clear the buffer
            acquired_data.clear()
        
        acq_toggle.setText("Start Acquisition")
        acq_toggle.setStyleSheet("")  # Reset button color

# Create and configure acquisition toggle button
acq_toggle = QtWidgets.QPushButton("Start Acquisition")
acq_toggle.setCheckable(True)
acq_toggle.setChecked(False)
acq_toggle.clicked.connect(toggle_acquisition)
control_layout.addWidget(acq_toggle)

# Add controls to plot
win.nextRow()
control_proxy.setWidget(control_widget)
win.addItem(control_proxy, row=2, col=0, colspan=2)

def smooth_track(track_array):
    """Apply moving average smoothing to track data"""
    if len(track_array) < SMOOTHING_WINDOW:
        return track_array
    
    # Separate components
    ranges = track_array[:, 0]
    angles = track_array[:, 1]
    velocities = track_array[:, 2]
    timestamps = track_array[:, 3]
    
    # Apply moving average to each component
    kernel = np.ones(SMOOTHING_WINDOW) / SMOOTHING_WINDOW
    smooth_ranges = np.convolve(ranges, kernel, mode='valid')
    smooth_angles = np.convolve(angles, kernel, mode='valid')
    smooth_velocities = np.convolve(velocities, kernel, mode='valid')
    
    # Pad the smoothed data to match original length
    pad_size = SMOOTHING_WINDOW - 1
    smooth_ranges = np.pad(smooth_ranges, (pad_size, 0), mode='edge')
    smooth_angles = np.pad(smooth_angles, (pad_size, 0), mode='edge')
    smooth_velocities = np.pad(smooth_velocities, (pad_size, 0), mode='edge')
    
    return np.column_stack((smooth_ranges, smooth_angles, smooth_velocities, timestamps))

def update_tracks(range_m, angle_deg, velocity_ms):
    """Update tracks with new detection (range, angle, velocity)"""
    global next_track_id

    current_time = time.time()
    new_point = [range_m, angle_deg, velocity_ms, current_time]
    
    # First, remove stale tracks
    active_tracks = []
    active_lines = []
    active_colors = []
    
    for i, (track, line, color) in enumerate(zip(tracks, track_lines, track_colors)):
        if track:  # Only check non-empty tracks
            last_update_time = track[-1][3]
            track_age = current_time - last_update_time
            if track_age <= MAX_TRACK_AGE:
                active_tracks.append(track)
                active_lines.append(line)
                active_colors.append(color)
    
    tracks[:] = active_tracks
    track_lines[:] = active_lines
    track_colors[:] = active_colors
    
    min_spatial_dist = float('inf')
    best_track_idx = None

    # Match detection to nearest active track (if any)
    for i, track in enumerate(tracks):
        if track:
            last_point = track[-1]
            spatial_dist, time_dist = calculate_distance(last_point, new_point)
            if spatial_dist < SPATIAL_THRESHOLD and time_dist < TIME_THRESHOLD and spatial_dist < min_spatial_dist:
                min_spatial_dist = spatial_dist
                best_track_idx = i

    if best_track_idx is not None:
        # Append to matched track
        tracks[best_track_idx].append(new_point)
        if len(tracks[best_track_idx]) > MAX_HISTORY:
            tracks[best_track_idx].pop(0)
    else:
        # Start new track
        tracks.append([new_point])
        new_line = create_track_line()
        track_lines.append(new_line)
        track_colors.append(generate_track_color(next_track_id - 1))

def update_track_display():
    """Update the display of all tracks"""
    current_time = time.time()
    
    # First update track lines
    active_tracks_info = []
    for track, line, color in zip(tracks, track_lines, track_colors):
        if track:  # If track has points
            track_array = np.array(track)
            
            # Apply smoothing to track data
            smoothed_track = smooth_track(track_array)
            
            # Calculate track statistics
            track_age = current_time - smoothed_track[-1, 3]
            avg_velocity = np.mean(np.abs(smoothed_track[:, 2]))
            track_length = len(track)
            
            # Create color gradient based on velocity and age
            alpha_values = np.linspace(0.2, 1.0, len(smoothed_track))
            vel_colors = [pg.mkBrush(*color, int(a*255)) for a in alpha_values]
            
            # Update track with velocity-based coloring
            line.setData(
                x=smoothed_track[:, 0],
                y=smoothed_track[:, 1],
                pen=pg.mkPen(color, width=2),
                symbolPen=None,
                symbolBrush=vel_colors,
                symbolSize=6
            )
            
            # Store track info for legend
            active_tracks_info.append({
                'id': tracks.index(track) + 1,
                'color': color,
                'range': smoothed_track[-1, 0],
                'angle': smoothed_track[-1, 1],
                'velocity': avg_velocity,
                'age': track_age,
                'points': track_length
            })
    
    # Update legend text
    if active_tracks_info:
        legend_html = '<div style="background-color: rgba(0, 0, 0, 0.7); padding: 10px; border-radius: 5px;">'
        for track in active_tracks_info:
            color_hex = rgb_to_hex(track['color'])
            legend_html += (
                f'<div style="color: {color_hex}; margin-bottom: 5px;">'
                f'Track {track["id"]}: '
                f'R={track["range"]:.1f}m, '
                f'θ={track["angle"]:.1f}°, '
                f'v={track["velocity"]:.1f}m/s'
                f'</div>'
            )
        legend_html += '</div>'
        legend_text.setHtml(legend_html)
    else:
        legend_text.setHtml('')

# Items for Range-Doppler plot
img_item = pg.ImageItem()
rd_plot.addItem(img_item)
scatter = pg.ScatterPlotItem(size=15, symbol='x', pen=pg.mkPen('r', width=2))
rd_plot.addItem(scatter)

# Scatter plot for Range-Angle detections
ra_scatter = pg.ScatterPlotItem(size=10, symbol='o', pen=None, brush=pg.mkBrush('y'))
ra_plot.addItem(ra_scatter)

# Text item for detection info
text_item = pg.TextItem(text='', color='y', anchor=(0, 1))
rd_plot.addItem(text_item)
text_item.setPos(ranges_m[-50], velocities_ms[-20])

# Color map
lut = pg.colormap.get('inferno').getLookupTable(0.0, 1.0, 256)
img_item.setLookupTable(lut)
img_item.setLevels([-50, 0])

# Timer
timer = QtCore.QTimer()

# Window functions
range_window = np.hanning(good_ramp_samples)
doppler_window = np.hanning(num_chirps)

def detect_strongest_scatterer(bursts_ch1, bursts_ch2):
    """
    Process both channels and detect the strongest scatterer's angle
    Returns: angle in degrees, RD1, RD2, peak_range_idx, peak_velocity_idx
    """
    # Apply range window
    bursts_ch1 =apply_clutter_cancellation(bursts_ch1)
    bursts_ch2 =apply_clutter_cancellation(bursts_ch2)

    bursts_ch1_windowed =  bursts_ch1 * range_window[None, :]
    bursts_ch2_windowed =  bursts_ch2 * range_window[None, :]
    
    # Range FFT with zero-padding for both channels
    R1 = np.fft.fft(bursts_ch1_windowed, n=range_fft_size, axis=1)
    R1 = R1[:, :range_fft_size//2]
    R2 = np.fft.fft(bursts_ch2_windowed, n=range_fft_size, axis=1)
    R2 = R2[:, :range_fft_size//2]

    
    # Apply Doppler window
    R1_windowed = R1 * doppler_window[:, None]
    R2_windowed = R2 * doppler_window[:, None]
    
    # Doppler FFT with zero-padding for both channels
    RD1 = np.fft.fftshift(np.fft.fft(R1_windowed, n=doppler_fft_size, axis=0), axes=0)
    RD2 = np.fft.fftshift(np.fft.fft(R2_windowed, n=doppler_fft_size, axis=0), axes=0)
    
    # Average magnitude to find strongest scatterer
    mag1 = np.abs(RD1)
    mag2 = np.abs(RD2)
    mag_avg = (mag1 + mag2) / 2
    
    # Mask out the zero-Doppler region (additional clutter suppression)
    center_doppler = doppler_fft_size // 2
    mask_width = 2 * DOPPLER_PAD_FACTOR  # Adjust mask width for zero-padding
    #mag_avg[center_doppler-mask_width:center_doppler+mask_width+1, :] *= 0.1
    #mag_avg[:, :20] = 0
    #mag_avg[:, 85:] = 0
    #RD1[:, :20] = 0
    #RD1[:, 85:] = 0

    ## Threshold detector ##

    # Parameters
    guard_cells_range = 4
    guard_cells_doppler = 4
    training_cells_range = 8
    training_cells_doppler = 8
    threshold_factor = 2.5
    
    # Total kernel size
    kr = training_cells_range + guard_cells_range
    kd = training_cells_doppler + guard_cells_doppler
    kernel_size = (2*kd + 1, 2*kr + 1)
    
    # Build kernel: ones everywhere except guard + cell-under-test (central region)
    kernel = np.ones(kernel_size, dtype=np.float32)
    kernel[kd - guard_cells_doppler : kd + guard_cells_doppler + 1,
        kr - guard_cells_range : kr + guard_cells_range + 1] = 0
    
    # Count of training cells
    n_training = np.sum(kernel)
    
    # Convolve with kernel to get local sums
    local_sum = convolve2d(mag_avg, kernel, mode='same', boundary='symm')
    noise_map = local_sum / n_training
    
    # Apply threshold (only where valid)
    valid_mask = np.zeros_like(mag_avg, dtype=bool)
    valid_mask[kd:-kd, kr:-kr] = True
    detections = (mag_avg > threshold_factor * noise_map) & valid_mask
    
    # Keep only values that pass threshold
    detection_map = np.zeros_like(mag_avg)
    detection_map[detections] = mag_avg[detections]
    
    # Find the strongest detection
    peak_velocity_idx, peak_range_idx = np.unravel_index(np.argmax(detection_map), detection_map.shape)
    
    # Extract phases at the strongest point
    spanWindow = 2
    phase1 = np.angle(RD1[peak_velocity_idx-spanWindow:peak_velocity_idx+spanWindow, peak_range_idx-spanWindow:peak_range_idx+spanWindow])
    phase2 = np.angle(RD2[peak_velocity_idx-spanWindow:peak_velocity_idx+spanWindow, peak_range_idx-spanWindow:peak_range_idx+spanWindow])
    
    # Calculate phase difference
    phase_diff = np.median(phase2 - phase1)
    phase_diff = np.mod(phase_diff + np.pi, 2 * np.pi) - np.pi
    
    # Convert phase difference to angle
    angle_rad = np.arcsin(phase_diff / (2 * np.pi * d))
    angle_deg = np.degrees(angle_rad)
    
    return angle_deg, RD1, RD2, peak_range_idx, peak_velocity_idx

def update():
    # receive raw IQ
    msg = pull.recv()
    
    raw = np.frombuffer(msg, dtype=np.complex64).reshape(2, -1)

    # slice each chirp for both channels
    bursts_ch1 = raw[0][idx]
    bursts_ch2 = raw[1][idx]

    # Store raw data if acquiring
    if is_acquiring:
        # Store only the sliced data for each channel
        frame_data = np.stack([bursts_ch1, bursts_ch2])
        acquired_data.append(frame_data)

    
    # optional LPF for both channels
    #bursts_ch1 = apply_lpf(bursts_ch1)
    #bursts_ch2 = apply_lpf(bursts_ch2)
    
    # Detect strongest scatterer and its angle
    angle_deg, RD1, RD2, peak_range_idx, peak_velocity_idx = detect_strongest_scatterer(bursts_ch1, bursts_ch2)
    
    # Get range and velocity of detection
    range_m = ranges_m[peak_range_idx]
    velocity_ms = velocities_ms[peak_velocity_idx]
    
    # Update tracks with new detection
    update_tracks(range_m, angle_deg, velocity_ms)
    update_track_display()
    
    # Display RD map (using channel 1)
    RD = RD1
    RD = RD / np.max(np.abs(RD))
    rd_db = 20 * np.log10(np.abs(RD) + 1e-12)
    
    # update image with proper scaling
    img_item.setImage(rd_db.T, autoLevels=False)
    
    # Update the scale of the plot
    img_item.setRect(pg.QtCore.QRectF(
        ranges_m[0],                    # xmin
        velocities_ms[0],               # ymin
        ranges_m[-1] - ranges_m[0],     # width
        velocities_ms[-1] - velocities_ms[0]  # height
    ))
    
    # Update RD marker position
    scatter.setData([range_m], [velocity_ms])
    
    # Update detection info text
    info_text = f"Range: {range_m:.1f} m\nVelocity: {velocity_ms:.1f} m/s\nAngle: {angle_deg:.1f}°"
    text_item.setText(info_text)

timer.timeout.connect(update)
timer.start(0)

app.exec()
pull.close()
ctx.term()