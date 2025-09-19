# Acquisition & Visualization Scripts

This folder contains Python utilities for acquiring, streaming, and visualizing radar data.  
The workflow is split between the **embedded platform** (Raspberry Pi + PlutoSDR + CN0566) and the **host PC**.

---

## 📂 Scripts Overview

### Acquisition (run on Raspberry Pi)

- **`raw_acquisition.py`**  
  Streams raw IQ chirp bursts (`[2, total_samples]`) from PlutoSDR + CN0566 via ZeroMQ.  
  Used for continuous capture without angular scanning.

- **`angular_acquisition.py`**  
  Performs an azimuth scan by electronically steering the 8-element array.  
  Produces a 3-D data cube (`[numAngles, samples, 2]`) and streams it via ZeroMQ.

### Visualization (run on host PC)

- **`radar_gui.py`**  
  Connects to **raw acquisition**, computes range–Doppler and single-angle estimates,  
  and maintains real-time target tracks. Supports saving `.npy` acquisitions.

- **`angular_gui.py`** *(renamed from `azMap_updated.py`)*  
  Connects to **angular acquisition**, computes and displays a live range–azimuth map  
  plus a history of detected peak angles.

---

## 🔗 Communication Model

- Acquisition scripts publish over **ZeroMQ PUSH** at `tcp://*:5555`.  
- GUI scripts connect as **PULL clients**, parse `complex64` arrays,  
  and update their visualizations in real time.

---

## 📐 Data Formats

- **Raw acquisition → GUI**: `[2, total_samples]`  
- **Angular acquisition → GUI**: `[numAngles, 2, samples]`  

Each GUI is specific to its acquisition script.

---

## ⚙️ Installation

On the **Raspberry Pi** (for acquisition):  
```bash
pip install -r pi_requirements.txt
```

On the **host PC** (for GUI):  
```bash
pip install -r requirements.txt
```

---

## ▶️ Usage

1. **Start one acquisition on Raspberry Pi**  
   ```bash
   python3 raw_acquisition.py
   # or
   python3 angular_acquisition.py
   ```

2. **Run the corresponding GUI on host PC**  
   ```bash
   python3 radar_gui.py      # for raw acquisition
   python3 angular_gui.py    # for angular acquisition
   ```

3. The GUIs connect by default to `tcp://phaser.local:5555`.  
   To change IP/port, edit the connection string in the GUI script.
