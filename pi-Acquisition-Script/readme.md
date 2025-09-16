# Acquisition Scripts

This folder contains Python utilities that work together to acquire, stream and visualize radar data.  
The workflow is split between the **embedded platform** (Raspberry Pi + PlutoSDR + CN0566) and the **host PC**.

## Scripts

- **raw_acquisition.py** *(run on Raspberry Pi)*  
  Streams raw IQ chirp bursts from PlutoSDR + CN0566 over a ZeroMQ socket.  
  Used for continuous real-time capture without angular scanning.

- **angular_acquisition.py** *(run on Raspberry Pi)*  
  Performs an azimuth scan by electronically steering the 8-element array.  
  Produces a 3-D data cube (*angle × samples × channels*) and streams it via ZeroMQ.

- **radar_gui.py** *(run on host PC)*  
  Connects to the ZeroMQ stream, computes range–Doppler and angle maps,  
  and maintains real-time target tracks. Includes acquisition controls  
  and the option to save data locally (`.npy`).

## Communication

All acquisition scripts publish data through a **ZeroMQ PUSH socket** (`tcp://*:5555`).  
The GUI (`radar_gui.py`) subscribes as a **PULL** client, parses the incoming `complex64` arrays,  
and updates its visualizations accordingly.

## Data Shapes

- **Raw acquisition** → `[2, total_samples]`  
- **Angular acquisition** → `[numAngles, samples, 2]`  
- **GUI** expects one of the above and builds range–Doppler/angle views in real time.
