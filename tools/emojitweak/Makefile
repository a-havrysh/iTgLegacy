SHELL := /bin/sh
HERE  := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
OUT   := $(HERE)out
FONT   := $(OUT)/AppleColorEmoji.ttf
FONT2X := $(OUT)/AppleColorEmoji@2x.ttf
PROBE := $(OUT)/emojiprobe2
IPAD  ?= 192.168.18.217

FONT_SRC := $(HERE)build.py $(HERE)emojidata.py $(HERE)fontasm.py \
            $(HERE)morxbuild.py $(HERE)raster.py

SDK_SEARCH := $(HERE)../../build/sdks/iPhoneOS12.4.sdk \
              $(HERE)../../build/sdks/iPhoneOS9.3.sdk
PROBE_SDK  ?= $(firstword $(wildcard $(SDK_SEARCH)))
PROBE_ARCH ?= armv7
PROBE_MIN  ?= 6.0

SOURCE_DATE_EPOCH ?= $(shell python3 -c 'import calendar,time; t=time.gmtime(); print(calendar.timegm((t.tm_year,t.tm_mon,t.tm_mday,0,0,0,0,0,0)))')
export SOURCE_DATE_EPOCH

.PHONY: deb font probe refresh clean distclean check pkgtest device-check install-ipad remove-ipad help

deb: $(FONT) $(FONT2X)
	@$(HERE)mkdeb.sh

$(FONT) $(FONT2X): $(FONT_SRC)
	@cd $(HERE) && python3 build.py

font: $(FONT) $(FONT2X)

probe: $(PROBE)

$(PROBE): $(HERE)emojiprobe2.m
	@test -n "$(PROBE_SDK)" || { \
	    echo "make: no armv7 iOS SDK found. Looked for:" >&2; \
	    for s in $(SDK_SEARCH); do echo "  $$s" >&2; done; \
	    echo "Set PROBE_SDK=/path/to/iPhoneOSx.y.sdk (needs an armv7 slice in" >&2; \
	    echo "libSystem.tbd; modern Xcode SDKs no longer have one)." >&2; \
	    exit 1; }
	@command -v ldid >/dev/null 2>&1 || { \
	    echo "make: ldid not found (brew install ldid); the probe must be" >&2; \
	    echo "pseudo-signed before an iOS 6 device will run it." >&2; exit 1; }
	@mkdir -p $(OUT)
	@xcrun --sdk iphoneos clang -arch $(PROBE_ARCH) -mthumb -O2 \
	    -isysroot $(PROBE_SDK) -miphoneos-version-min=$(PROBE_MIN) -fno-objc-arc \
	    -framework CoreText -framework CoreGraphics -framework ImageIO \
	    -framework MobileCoreServices -framework Foundation \
	    -o $(PROBE) $(HERE)emojiprobe2.m
	@ldid -S $(PROBE)
	@echo "built $(PROBE) ($(PROBE_ARCH), SDK $(notdir $(PROBE_SDK)))"

refresh:
	@rm -f $(HERE)cache/emoji-latest-ReadMe.txt $(HERE)cache/twemoji-release.json
	@rm -rf $(HERE)cache/twemoji
	@rm -f $(FONT) $(FONT2X) $(OUT)/COPYING
	@echo "unpinned Unicode and Twemoji; now run: make deb"
	@echo "old raster caches are keyed by Twemoji tag and can be deleted:"
	@ls -1 $(HERE)work/strikes-*.pickle 2>/dev/null || true

check:
	@cd $(HERE) && python3 coverage.py

pkgtest: $(FONT) $(FONT2X)
	@$(HERE)pkgtest.sh

device-check: $(PROBE)
	@cd $(HERE) && IPAD=$(IPAD) python3 devicecheck.py

install-ipad: deb $(PROBE)
	@cd $(HERE) && IPAD=$(IPAD) ./debtest.sh install

remove-ipad: $(PROBE)
	@cd $(HERE) && IPAD=$(IPAD) ./debtest.sh remove

clean:
	@rm -rf $(HERE)work/deb $(HERE)work/pkgtest $(OUT)/*.deb

distclean: clean
	@rm -rf $(HERE)work $(OUT)

help:
	@echo "make deb           build both payload fonts if needed, then the .deb"
	@echo "make font          build the fonts only (1x and @2x strike sets)"
	@echo "make probe         cross-compile out/emojiprobe2 for the device"
	@echo "make refresh       unpin Unicode/Twemoji so the next build picks up new releases"
	@echo "make check         host-side coverage check (HarfBuzz)"
	@echo "make pkgtest       host-side test of the maintainer scripts (1x/2x/both/neither)"
	@echo "make device-check  device-side CoreText coverage check (needs IPAD=<ip>)"
	@echo "make install-ipad  build the .deb, install it, verify on the device"
	@echo "make remove-ipad   remove the package, verify the stock font is back"
	@echo "make clean         drop the .deb staging tree and built .deb files"
	@echo "make distclean     also drop out/ and the raster cache"
