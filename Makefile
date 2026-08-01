# Spartan-3E Drum Machine - ISE 14.7 CLI Build
DESIGN  := top
PART    := xc3s500e-fg320-4
UCF     := ../constraints/top.ucf
BUILDDIR := build

VHDL_SRC := $(wildcard src/**/*.vhd) $(wildcard src/*.vhd)

.PHONY: all clean program dac_test program_dac_test clean_dac_test

all: $(BUILDDIR)/$(DESIGN).bit

$(BUILDDIR)/xst/tmp:
	mkdir -p $@

# Synthesis
$(BUILDDIR)/$(DESIGN).ngc: $(VHDL_SRC) $(BUILDDIR)/top.xst $(BUILDDIR)/top.prj | $(BUILDDIR)/xst/tmp
	cd $(BUILDDIR) && xst -ifn top.xst -ofn top.syr

# Translate
$(BUILDDIR)/$(DESIGN).ngd: $(BUILDDIR)/$(DESIGN).ngc constraints/top.ucf
	cd $(BUILDDIR) && ngdbuild -dd _ngo -nt timestamp -uc $(UCF) -p $(PART) top.ngc top.ngd

# Map
$(BUILDDIR)/$(DESIGN)_map.ncd: $(BUILDDIR)/$(DESIGN).ngd
	cd $(BUILDDIR) && map -p $(PART) -w -o top_map.ncd top.ngd top.pcf

# Place & Route
$(BUILDDIR)/$(DESIGN).ncd: $(BUILDDIR)/$(DESIGN)_map.ncd
	cd $(BUILDDIR) && par -w top_map.ncd top.ncd top.pcf

# Bitstream
$(BUILDDIR)/$(DESIGN).bit: $(BUILDDIR)/$(DESIGN).ncd
	cd $(BUILDDIR) && bitgen -w -g StartUpClk:JtagClk -g UnusedPin:PullNone top.ncd top.bit top.pcf

# Program via xc3sprog
program: $(BUILDDIR)/$(DESIGN).bit
	sudo xc3sprog -c xpc -p 0 $<

# =============================================================================
# DAC/SPI standalone test harness (bypasses sequencer/mixer/voices/UI).
# Builds and programs independently of the main `top` design above.
# See src/dac_test.vhd for what it does and how to interpret scope results.
# =============================================================================
DAC_TEST_UCF := ../constraints/dac_test.ucf

$(BUILDDIR)/xst/tmp_dac_test:
	mkdir -p $@

build/dac_test.ngc: src/dac_test.vhd src/infrastructure/dac_driver.vhd src/infrastructure/spi_master.vhd src/infrastructure/sine_table.vhd $(BUILDDIR)/dac_test.xst $(BUILDDIR)/dac_test.prj | $(BUILDDIR)/xst/tmp_dac_test
	cd $(BUILDDIR) && xst -ifn dac_test.xst -ofn dac_test.syr

build/dac_test.ngd: build/dac_test.ngc constraints/dac_test.ucf
	cd $(BUILDDIR) && ngdbuild -dd _ngo_dac_test -nt timestamp -uc $(DAC_TEST_UCF) -p $(PART) dac_test.ngc dac_test.ngd

build/dac_test_map.ncd: build/dac_test.ngd
	cd $(BUILDDIR) && map -p $(PART) -w -o dac_test_map.ncd dac_test.ngd dac_test.pcf

build/dac_test.ncd: build/dac_test_map.ncd
	cd $(BUILDDIR) && par -w dac_test_map.ncd dac_test.ncd dac_test.pcf

build/dac_test.bit: build/dac_test.ncd
	cd $(BUILDDIR) && bitgen -w -g StartUpClk:JtagClk -g UnusedPin:PullNone dac_test.ncd dac_test.bit dac_test.pcf

dac_test: build/dac_test.bit

program_dac_test: build/dac_test.bit
	sudo xc3sprog -c xpc -p 0 $<

clean_dac_test:
	rm -rf $(BUILDDIR)/xst_dac_test $(BUILDDIR)/_ngo_dac_test $(BUILDDIR)/xst/tmp_dac_test
	rm -f $(BUILDDIR)/dac_test.ngc $(BUILDDIR)/dac_test.ngd $(BUILDDIR)/dac_test.ncd $(BUILDDIR)/dac_test.pcf
	rm -f $(BUILDDIR)/dac_test.bit $(BUILDDIR)/dac_test.bgn $(BUILDDIR)/dac_test.bld $(BUILDDIR)/dac_test.drc
	rm -f $(BUILDDIR)/dac_test_map.ncd $(BUILDDIR)/dac_test_map.mrp $(BUILDDIR)/dac_test_map.ngm
	rm -f $(BUILDDIR)/dac_test.par $(BUILDDIR)/dac_test.pad $(BUILDDIR)/dac_test.xpi $(BUILDDIR)/dac_test.unroutes
	rm -f $(BUILDDIR)/dac_test.syr $(BUILDDIR)/dac_test*.xrpt $(BUILDDIR)/dac_test_pad.*

clean:
	rm -rf $(BUILDDIR)/xst $(BUILDDIR)/_ngo
	rm -f $(BUILDDIR)/*.ngc $(BUILDDIR)/*.ngd $(BUILDDIR)/*.ncd $(BUILDDIR)/*.pcf
	rm -f $(BUILDDIR)/*.bit $(BUILDDIR)/*.bgn $(BUILDDIR)/*.bld $(BUILDDIR)/*.drc
	rm -f $(BUILDDIR)/*.map $(BUILDDIR)/*.mrp $(BUILDDIR)/*.ngm $(BUILDDIR)/*.syr
	rm -f $(BUILDDIR)/*.par $(BUILDDIR)/*.pad $(BUILDDIR)/*.xpi $(BUILDDIR)/*.unroutes
	rm -f $(BUILDDIR)/*.twx $(BUILDDIR)/*.xwbt $(BUILDDIR)/*.lst $(BUILDDIR)/*.srp
	rm -f $(BUILDDIR)/*.lso $(BUILDDIR)/*.ngr $(BUILDDIR)/*.ptwx $(BUILDDIR)/*.xrpt
	rm -f $(BUILDDIR)/*_pad.csv $(BUILDDIR)/*_pad.txt
	rm -f $(BUILDDIR)/*_summary.xml $(BUILDDIR)/*_usage.xml
	rm -f $(BUILDDIR)/usage_statistics_webtalk.html $(BUILDDIR)/webtalk.log
