SHELL := /bin/sh
HERE  := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
OUT   := $(HERE)out
FONT  := $(OUT)/AppleColorEmoji.ttf
IPAD  ?= 192.168.18.217

.PHONY: deb font clean distclean check device-check install-ipad remove-ipad help

deb: $(FONT)
	@$(HERE)mkdeb.sh

$(FONT):
	@cd $(HERE) && python3 build.py

font: $(FONT)

check:
	@cd $(HERE) && python3 coverage.py

device-check:
	@cd $(HERE) && IPAD=$(IPAD) python3 devicecheck.py

install-ipad: deb
	@cd $(HERE) && IPAD=$(IPAD) ./debtest.sh install

remove-ipad:
	@cd $(HERE) && IPAD=$(IPAD) ./debtest.sh remove

clean:
	@rm -rf $(HERE)work/deb $(OUT)/*.deb

distclean: clean
	@rm -rf $(HERE)work $(OUT)

help:
	@echo "make deb           build out/AppleColorEmoji.ttf if needed, then the .deb"
	@echo "make font          build the font only"
	@echo "make check         host-side coverage check (HarfBuzz)"
	@echo "make device-check  device-side CoreText coverage check (needs IPAD=<ip>)"
	@echo "make install-ipad  build the .deb, install it, verify on the device"
	@echo "make remove-ipad   remove the package, verify the stock font is back"
	@echo "make clean         drop the .deb staging tree and built .deb files"
	@echo "make distclean     also drop out/ and the raster cache"
