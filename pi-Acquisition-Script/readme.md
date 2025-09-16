# Data Acquisition Scripts

This folder contains Python utilities for capturing and streaming radar data to the main GUI.

## Scripts

- **raw_acquisition.py**  
  Streams raw IQ chirp bursts from PlutoSDR + CN0566 over a ZeroMQ socket.  
  Useful for real-time capture when no angle scan is required.

- **angular_acquisition.py**  
  Performs an azimuth scan across a set of steering angles by re-phasing the 8-element array.  
  Produces a 3-D data cube (*angle × samples × channels*) and streams it via ZeroMQ.

## Output Interface

Both scripts publish data on a **ZeroMQ PUSH socket** (`tcp://*:5555`).  
A client can subscribe with a matching **PULL** socket and parse the incoming `complex64` arrays.

## Data Shapes

- **Raw acquisition** → `[2, total_samples]`  
- **Angular acquisition** → `[numAngles, samples, 2]`  

