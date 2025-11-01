#create_clock -period 20.000 -name clock -waveform {0.000 10.000} [get_ports clk]

set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN T22} [get_ports {LED[0]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN T21} [get_ports {LED[1]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN U22} [get_ports {LED[2]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN U21} [get_ports {LED[3]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN V22} [get_ports {LED[4]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN W22} [get_ports {LED[5]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN U19} [get_ports {LED[6]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN U14} [get_ports {LED[7]}]

set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN F22} [get_ports {SWITCH[0]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN G22} [get_ports {SWITCH[1]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN H22} [get_ports {SWITCH[2]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN F21} [get_ports {SWITCH[3]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN H19} [get_ports {SWITCH[4]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN H18} [get_ports {SWITCH[5]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN H17} [get_ports {SWITCH[6]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN M15} [get_ports {SWITCH[7]}]

set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN T18} [get_ports {BTNU}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN R18} [get_ports {BTNR}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN R16} [get_ports {BTND}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN P16} [get_ports {BTNC}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN N15} [get_ports {BTNL}]

# Allow loop for ring oscillator
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets */calculate_dynamics[*].*/rand_i/rand_raw_i/ros[*].ro/w*]

