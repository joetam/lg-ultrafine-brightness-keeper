SWIFTC := xcrun swiftc
SOURCE := Sources/main.swift
PRODUCT := build/lg-ultrafine-brightness-keeper
ARCH := $(shell uname -m)
MACOSX_DEPLOYMENT_TARGET ?= 13.0

.PHONY: all clean test hardware-check

all: $(PRODUCT)

$(PRODUCT): $(SOURCE)
	@mkdir -p build
	MACOSX_DEPLOYMENT_TARGET=$(MACOSX_DEPLOYMENT_TARGET) $(SWIFTC) \
		-target $(ARCH)-apple-macos$(MACOSX_DEPLOYMENT_TARGET) \
		-O -warnings-as-errors \
		-framework AppKit \
		-framework CoreGraphics \
		-o $(PRODUCT) \
		$(SOURCE)

test: $(PRODUCT)
	$(PRODUCT) --self-test

hardware-check: $(PRODUCT)
	$(PRODUCT) --list

clean:
	rm -f $(PRODUCT)
