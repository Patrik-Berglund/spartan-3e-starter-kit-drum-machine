# Spartan-3E Drum Machine - ISE 14.7 CLI Build
DESIGN  := top
PART    := xc3s500e-fg320-4
UCF     := ../constraints/top.ucf
BUILDDIR := build

VHDL_SRC := $(wildcard src/**/*.vhd) $(wildcard src/*.vhd)

.PHONY: all clean program

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
