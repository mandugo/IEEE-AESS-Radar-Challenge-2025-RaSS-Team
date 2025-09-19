# Radar Application Parameters

## Radar Configuration
| Parameter      | Value        | Description                        |
|----------------|--------------|------------------------------------|
| num_chirps     | 64           | Number of chirps per frame         |
| ramp_time_us   | 500 μs       | Chirp duration                     |
| sample_rate    | 0.6e6 Hz     | ADC sampling rate                  |
| chirp_bw       | 400e6 Hz     | Chirp bandwidth                    |
| fc             | 10.2e9 Hz    | Radar center frequency             |
| c              | 3e8 m/s      | Speed of light                     |
| lambda         | c / fc       | Wavelength                         |
| d_lambda       | 2            | Antenna spacing in wavelengths     |


## Display / Processing Defaults
| Parameter         | Value   | Description                               |
|-------------------|---------|-------------------------------------------|
| R_MAX             | 25 m    | Maximum display range                     |
| colormap_levels   | 32      | Levels in colormap                        |
| Pfa               | 1e-4    | Probability of false alarm                |
| guard_r           | 5       | Range guard cells                         |
| guard_d           | 5       | Doppler guard cells                       |
| train_r           | 15      | Range training cells                      |
| train_d           | 15      | Doppler training cells                    |
| apply_clutter     | true    | Apply clutter removal                     |
| bypass_nulling    | true    | Bypass nulling option                     |
| null_angle_deg    | 8.4°    | Nulling angle                             |

## Video Defaults
| Parameter | Value  | Description                                    |
|-----------|--------|------------------------------------------------|
| t0        | 0.0 s  | Time offset (positive = video delayed)         |
| speed     | 2.7    | Video speed factor vs radar time               |

## Application State
| Parameter          | Value    | Description                          |
|--------------------|----------|--------------------------------------|
| MAX_HISTORY        | 1000     | Max number of points per track       |
| SPATIAL_THRESHOLD  | 2.0      | Spatial association threshold        |
| TIME_THRESHOLD     | 2.0      | Temporal association threshold       |
