###############################################################################
#                                                                             #
# Copyright 2016 myStorm Copyright and related                                #
# rights are licensed under the Solderpad Hardware License, Version 0.51      #
# (the “License”); you may not use this file except in compliance with        #
# the License. You may obtain a copy of the License at                        #
# http://solderpad.org/licenses/SHL-0.51. Unless required by applicable       #
# law or agreed to in writing, software, hardware and materials               #
# distributed under this License is distributed on an “AS IS” BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or             #
# implied. See the License for the specific language governing                #
# permissions and limitations under the License.                              #
#                                                                             #
###############################################################################

VERILOG_FILES = hdmitest.v

chip.bin: $(VERILOG_FILES) hdmi.pcf
	yosys -q -p "synth_ice40 -dffe_min_ce_use 4 -json chip.json" $(VERILOG_FILES)
#	yosys -q -p "synth_ice40 -blif chip.blif" $(VERILOG_FILES)
#	arachne-pnr -d 8k -P tq144:4k -p hdmi.pcf chip.blif -o chip.txt
	nextpnr-ice40 --freq 30 --up5k --package sg48 --json chip.json --pcf hdmi.pcf --asc chip.txt --opt-timing
	icetime -d hx8k -P tq144:4k chip.txt
	icepack chip.txt chip.bin


.PHONY: upload
upload: chip.bin
	iceprog chip.bin

.PHONY: clean
clean:
	$(RM) -f chip.blif chip.txt chip.ex chip.bin chip.json waves.vcd tb


flash: 
	dfu-util -d 0483:df11 --alt 0 --dfuse-address 0x0801F000 -D chip.bin

run:
	stty -F /dev/ttyUSB0 115200 raw
	cat /dev/ttyUSB0

tb: tb.v $(VERILOG_FILES)
	iverilog -o tb tb.v $(VERILOG_FILES)

sim: tb
	./tb

help:
	@echo "Makefile options:"
	@echo "    chip.bin (default): Create iCE40 bitstream"
	@echo "    upload:             Upload chip.bin as volatible bitstream to FPGA. Run as root."
	@echo "    flash:              Flash chip.bin into STM32 internal flash. STM32 must be in DFU mode. Run as root."
	@echo "    sim:                Simulate the design. Create .vcd file to use with GTKwave."
	@echo "    run:                Check results on USB2 port."
	@echo "    clean:              Clean up directory"

