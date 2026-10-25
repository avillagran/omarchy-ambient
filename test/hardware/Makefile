# Tools for trying the screensaver on a real Hyprland session; see README.md.
BUILD := ../../build/hardware

all: $(BUILD)/vpointer

$(BUILD)/wlr-virtual-pointer-unstable-v1-client.h: wlr-virtual-pointer-unstable-v1.xml
	mkdir -p $(BUILD)
	wayland-scanner client-header $< $@

$(BUILD)/wlr-virtual-pointer-unstable-v1.c: wlr-virtual-pointer-unstable-v1.xml
	mkdir -p $(BUILD)
	wayland-scanner private-code $< $@

$(BUILD)/vpointer: vpointer.c $(BUILD)/wlr-virtual-pointer-unstable-v1.c $(BUILD)/wlr-virtual-pointer-unstable-v1-client.h
	$(CC) -O2 -Wall -I$(BUILD) -o $@ vpointer.c $(BUILD)/wlr-virtual-pointer-unstable-v1.c $(shell pkg-config --cflags --libs wayland-client)

.PHONY: all
