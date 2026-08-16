SHELL := /bin/sh
HERE  := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
ROOT  := $(abspath $(HERE)/../..)
OUT   := $(HERE)/out
SRC   := $(HERE)/src

DYLIB   := $(OUT)/EmojiKeyboard.dylib
PREP    := $(OUT)/emojipaletteprep
PALETTE := $(OUT)/palette.plist

XCODE_DEV := $(shell xcode-select -p)
CLANG     := $(XCODE_DEV)/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang

SDK ?= $(ROOT)/build/sdks/iPhoneOS12.4.sdk
ifeq ($(wildcard $(SDK)),)
  SDK := $(ROOT)/build/sdks/iPhoneOS9.3.sdk
endif
ifeq ($(wildcard $(SDK)),)
  SDK := $(XCODE_DEV)/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk
endif

ARCH     := -arch armv7
MIN      := -miphoneos-version-min=6.0
WARN     := -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations
CFLAGS   := $(ARCH) -isysroot $(SDK) $(MIN) $(WARN) -O2 -fno-objc-arc \
            -fobjc-exceptions -I$(SRC)
FRAMEWORKS := -framework Foundation -framework CoreText -framework CoreGraphics

LDID := $(shell command -v ldid 2>/dev/null)

.PHONY: all dylib prep palette deb clean distclean check help

all: dylib prep palette

dylib: $(DYLIB)
prep: $(PREP)
palette: $(PALETTE)

$(OUT):
	@mkdir -p $(OUT)

$(DYLIB): $(SRC)/EKPalette.m $(SRC)/EKTweak.m $(SRC)/EKPalette.h | $(OUT)
	@echo "  dylib   $(notdir $@)  (sdk $(notdir $(SDK)))"
	@$(CLANG) $(CFLAGS) -dynamiclib \
		-install_name /Library/MobileSubstrate/DynamicLibraries/EmojiKeyboard.dylib \
		$(FRAMEWORKS) -o $@ $(SRC)/EKPalette.m $(SRC)/EKTweak.m
	@if [ -n "$(LDID)" ]; then $(LDID) -S $@; else echo "  warning: ldid not found, $(notdir $@) is unsigned"; fi

$(PREP): $(SRC)/EKPalette.m $(SRC)/EKPrep.m $(SRC)/EKPalette.h | $(OUT)
	@echo "  binary  $(notdir $@)"
	@$(CLANG) $(CFLAGS) $(FRAMEWORKS) -o $@ $(SRC)/EKPalette.m $(SRC)/EKPrep.m
	@if [ -n "$(LDID)" ]; then $(LDID) -S $@; else echo "  warning: ldid not found, $(notdir $@) is unsigned"; fi

$(PALETTE): $(HERE)/build.py $(HERE)/evidence/ios6_emoji_tables.json | $(OUT)
	@cd $(HERE) && python3 build.py

deb: all
	@$(HERE)/mkdeb.sh

check: $(DYLIB) $(PREP) $(PALETTE)
	@cd $(HERE) && python3 verify.py
	@$(HERE)/hostcheck.sh

clean:
	@rm -rf $(HERE)/work/deb $(OUT)/*.deb

distclean:
	@rm -rf $(HERE)/work $(OUT)

help:
	@echo "make            build the dylib, the prep tool and the palette data"
	@echo "make deb        also package everything as a .deb"
	@echo "make check      static checks on the built products"
	@echo "make clean      drop the .deb staging tree and built .deb files"
	@echo "make distclean  drop out/ and work/ entirely"
	@echo ""
	@echo "SDK=<path>                      override the iOS SDK"
	@echo "EMOJITWEAK_DIR=<path>           override the font project (for emoji-test.txt)"
	@echo "EMOJIKEYBOARD_SKIN_TONES=0      leave skin-tone sequences out of the data"
	@echo "EMOJIKEYBOARD_FONTPACKAGE=<id>  which font package to depend on"
	@echo "EMOJIKEYBOARD_FONTDEP=<mode>    depends (default), recommends or none"
	@echo ""
	@echo "See the README for the rest of the mkdeb.sh overrides, and for how to"
	@echo "switch the tweak off from SSH if it ever misbehaves."
