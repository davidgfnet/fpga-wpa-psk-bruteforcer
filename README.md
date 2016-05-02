
FPGA WPA-PSK bruteforcer
========================

WPA-PSK bruteforcing using FPGA devices.
This should work well with Cairnsmore1 devices, will require
flashing the Spartan-3 controller FPGA though (check 
board/controller for sources and driver manager).

The verilog is located in src/ where you can find some
test-bench infrastructure. The driver is locate under driver/
and it allows you to generate testbench files (need to be 
converted to vectors through conv.py though).

Feel free to contact me if you struggle to make it work :)
Oh find binaries under bin/ if you are just too lazy to build
the shit yourself :)

