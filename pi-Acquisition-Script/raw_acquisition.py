import sys
import time
import numpy as np
import matplotlib.pyplot as plt
import zmq
from matplotlib.animation import FuncAnimation


'''This script uses the new Pluto TDD engine
   As of March 2024, this is in the main branch of https://github.com/analogdevicesinc/pyadi-iio
   This script only works with Pluto rev 0.39 (or later)
'''
import adi
print(adi.__version__)

'''Key Parameters'''
null_angle_deg = None # Hardcoded null angle in degrees
sample_rate = 0.6e6
center_freq = 2.1e9
rx_gain = 70   # must be between -3 and 70
output_freq = 10.2e9
default_chirp_bw = 0.4e9
num_chirps=64
ramp_time = 500      # ramp time in us
num_slices = 50     # this sets how much time will be displayed on the waterfall plot
plot_freq = 0    # x-axis freq range to plot

S = default_chirp_bw/(ramp_time*1e-6)
f_offset = 1.5*2*S/3e8 #1.5 meters are required to correct range bias
signal_freq = 0 #-f_offset
clockCycles=int(ramp_time)
startBias=5
# %%
""" Program the basic hardware settings
"""
# Instantiate all the Devices
rpi_ip = "ip:phaser.local"  # IP address of the Raspberry Pi
sdr_ip = "ip:192.168.2.1"  # "192.168.2.1, or pluto.local"  # IP address of the Transceiver Block
my_sdr = adi.ad9361(uri=sdr_ip)
my_phaser = adi.CN0566(uri=rpi_ip, sdr=my_sdr)

# Initialize both ADAR1000s, set gains to max, and all phases to 0
my_phaser.configure(device_mode="rx")
my_phaser.element_spacing = 0.014
my_phaser.load_gain_cal()
my_phaser.load_phase_cal()
for i in range(0, 8):
    my_phaser.set_chan_phase(i, 0)

gain_list = [8, 34, 84, 127, 127, 84, 34, 8]  # Blackman taper
#gain_list = [127, 127, 127, 127, 127, 127, 127,127] #Uniform taper
for i in range(0, len(gain_list)):
    my_phaser.set_chan_gain(i, gain_list[i], apply_cal=True)

# Setup Raspberry Pi GPIO states
my_phaser._gpios.gpio_tx_sw = 0  # 0 = TX_OUT_2, 1 = TX_OUT_1
my_phaser._gpios.gpio_vctrl_1 = 1 # 1=Use onboard PLL/LO source  (0=disable PLL and VCO, and set switch to use external LO input)
my_phaser._gpios.gpio_vctrl_2 = 1 # 1=Send LO to transmit circuitry  (0=disable Tx path, and send LO to LO_OUT)

# Configure SDR Rx
my_sdr.sample_rate = int(sample_rate)
sample_rate = int(my_sdr.sample_rate)
my_sdr.rx_lo = int(center_freq)
my_sdr.rx_enabled_channels = [0, 1]  # enable Rx1 and Rx2
my_sdr.gain_control_mode_chan0 = "manual"  # manual or slow_attack
my_sdr.gain_control_mode_chan1 = "manual"  # manual or slow_attack
my_sdr.rx_hardwaregain_chan0 = int(rx_gain)  # must be between -3 and 70
my_sdr.rx_hardwaregain_chan1 = int(rx_gain)  # must be between -3 and 70

# Configure SDR Tx
my_sdr.tx_lo = int(center_freq)
my_sdr.tx_enabled_channels = [0, 1]
my_sdr.tx_cyclic_buffer = True  # must set cyclic buffer to true for the tdd burst mode.
my_sdr.tx_hardwaregain_chan0 = -88  # must be between 0 and -88
my_sdr.tx_hardwaregain_chan1 = 0  # must be between 0 and -88

# Configure the ADF4159 Ramping PLL
vco_freq = int(output_freq + signal_freq + center_freq)
BW = default_chirp_bw
num_steps = int(ramp_time)    # in general it works best if there is 1 step per us
my_phaser.frequency = int(vco_freq / 4)
my_phaser.freq_dev_range = int(BW / 4)      # total freq deviation of the complete freq ramp in Hz
my_phaser.freq_dev_step = int((BW / 4) / num_steps)  # This is fDEV, in Hz.  Can be positive or negative
my_phaser.freq_dev_time = int(ramp_time)  # total time (in us) of the complete frequency ramp
print("requested freq dev time = ", ramp_time)
my_phaser.delay_word = 4095  # 12 bit delay word.  4095*PFD = 40.95 us.  For sawtooth ramps, this is also the length of the Ramp_complete signal
my_phaser.delay_clk = "PFD*CLK1"  # can be 'PFD' or 'PFD*CLK1'
my_phaser.delay_start_en = 0  # delay start
my_phaser.ramp_delay_en = 1  # delay between ramps.
my_phaser.trig_delay_en = 0  # triangle delay
my_phaser.ramp_mode = "single_sawtooth_burst"  # ramp_mode can be:  "disabled", "continuous_sawtooth", "continuous_triangular", "single_sawtooth_burst", "single_ramp_burst"
my_phaser.sing_ful_tri = 0  # full triangle enable/disable -- this is used with the single_ramp_burst mode
my_phaser.tx_trig_en = 1  # start a ramp with TXdata
my_phaser.enable = 0  # 0 = PLL enable.  Write this last to update all the registers

# %%
""" Synchronize chirps to the start of each Pluto receive buffer
"""
# Configure TDD controller
sdr_pins = adi.one_bit_adc_dac(sdr_ip)
sdr_pins.gpio_tdd_ext_sync = True # If set to True, this enables external capture triggering using the L24N GPIO on the Pluto.  When set to false, an internal trigger pulse will be generated every second
tdd = adi.tddn(sdr_ip)
sdr_pins.gpio_phaser_enable = True
tdd.enable = False         # disable TDD to configure the registers
tdd.sync_external = True
tdd.startup_delay_ms = 0
ramp_time_ms=ramp_time/1e3
PRI_ms = ramp_time_ms
tdd.frame_length_ms = PRI_ms    # each chirp is spaced this far apart
tdd.burst_count = num_chirps       # number of chirps in one continuous receive buffer

# — Channel 0: drive the PLL ramp for exactly ramp_time_ms —
tdd.channel[0].enable = True
tdd.channel[0].polarity = False
tdd.channel[0].on_raw = startBias
tdd.channel[0].off_raw = clockCycles+startBias

# — Channel 1: open ADC window only after the PLL ramp settles —
tdd.channel[1].enable = True
tdd.channel[1].polarity = False
tdd.channel[1].on_raw = startBias
tdd.channel[1].off_raw = clockCycles+startBias

#tdd.channel[1].enable   = True
#tdd.channel[1].polarity = False
#tdd.channel[1].on_ms    = 0.1   # wait 0.1 ms for stability
#tdd.channel[1].off_ms   = ramp_time_ms

# You can disable Channel 2 if unused
tdd.channel[2].enable = True
tdd.channel[2].polarity = False
tdd.channel[2].on_raw = startBias
tdd.channel[2].off_raw = clockCycles+startBias

# Finally turn TDD on
tdd.enable = True

num_samples_frame = int(tdd.frame_length_ms/1000*sample_rate)
print(num_samples_frame)
# From start of each ramp, how many "good" points do we want?
# For best freq linearity, stay away from the start of the ramps
ramp_time = int(my_phaser.freq_dev_time)
ramp_time_s = ramp_time / 1e6
begin_offset_time = 0.3 * ramp_time_s   # time in seconds
print("actual freq dev time = ", ramp_time)
good_ramp_samples = int((ramp_time_s-begin_offset_time) * sample_rate)
print('Good ramp samples',good_ramp_samples)
start_offset_time = tdd.channel[0].on_ms/1e3 + begin_offset_time
start_offset_samples = int(start_offset_time * sample_rate)

# Pluto receive buffer size needs to be greater than total time for all chirps
total_time = tdd.frame_length_ms * num_chirps   # time in ms
print("Total Time for all Chirps:  ", total_time, "ms")
buffer_time = 0
power=4
while total_time > buffer_time:
    power=power+1
    buffer_size = int(2**power)
    buffer_time = buffer_size/my_sdr.sample_rate*1000   # buffer time in ms
    if power==23:
        break     # max pluto buffer size is 2**23, but for tdd burst mode, set to 2**22
print("buffer_size:", buffer_size)
my_sdr.rx_buffer_size = buffer_size
print("buffer_time:", buffer_time, " ms")

""" Create a sinewave waveform for Pluto's transmitter
"""
N = int(2**18)
fc = int(signal_freq)
ts = 1 / float(sample_rate)
t = np.arange(0, N * ts, ts)
i = np.cos(2 * np.pi * t * fc) * 2 ** 14
q = np.sin(2 * np.pi * t * fc) * 2 ** 14
iq = 1 * (i + 1j * q)

# transmit data from Pluto
my_sdr._ctx.set_timeout(30000)
my_sdr._rx_init_channels()
my_sdr.tx([iq, iq])

# Precompute the “1.5-sample” index matrix
n      = np.arange(num_chirps)
starts = start_offset_samples + np.floor(n * (num_samples_frame+0.5)).astype(int)
cols   = np.arange(good_ramp_samples)
idx    = starts[:, None] + cols[None, :]

# ZeroMQ PUSH socket (blocking)
ctx    = zmq.Context()
push   = ctx.socket(zmq.PUSH)
push.bind("tcp://*:5555")

#Nulling
frequency = output_freq  # Operating frequency in Hz (should match output_freq)
num_elements = 8
wavelength = 3e8 / frequency
if not null_angle_deg == None:
    # Calculate the phase values for the null
    null_phase_values = np.zeros(num_elements)
    null_angle_rad = np.deg2rad(null_angle_deg)
    for n in range(num_elements):
        phase = 2 * np.pi * my_phaser.element_spacing * n * np.cos(null_angle_rad) / wavelength
        null_phase_values[n] = -np.rad2deg(phase) # Apply negative for nulling

    # Apply the nulling phases to the analog phaser
    for i in range(num_elements):
        phaseVal = null_phase_values[i]
        my_phaser.set_chan_phase(i, phaseVal)
else:
    # Apply the nulling phases to the analog phaser
    for i in range(num_elements):
        my_phaser.set_chan_phase(i, 0)


while True:
    # 1) Trigger a burst
    my_phaser._gpios.gpio_burst = 0
    my_phaser._gpios.gpio_burst = 1
    my_phaser._gpios.gpio_burst = 0

    # 2) Grab entire RX buffer for both channels
    data = my_sdr.rx()           # shape (2, total_samples)
    buf  = np.ascontiguousarray(data, dtype=np.complex64).tobytes()
    push.send(buf)
    # 3) Send raw IQ bytes directly
    #push.send(data.tobytes())