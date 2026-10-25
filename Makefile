PREFIX ?= /usr/local
DESTDIR ?=

BUILD := build
VENDOR := vendor/gtk4-layer-shell
PROTOCOLS := $(shell pkg-config --variable=pkgdatadir wayland-protocols)
XML := $(VENDOR)/protocol/wlr-layer-shell-unstable-v1.xml \
	$(PROTOCOLS)/stable/xdg-shell/xdg-shell.xml \
	$(PROTOCOLS)/staging/ext-session-lock/ext-session-lock-v1.xml
NAMES := $(basename $(notdir $(XML)))
HEADERS := $(NAMES:%=$(BUILD)/%-client.h)
GLUE := $(NAMES:%=$(BUILD)/%.c)
SOURCES := layer/omarchy-bg-live-layer.c $(wildcard $(VENDOR)/src/*.c) $(GLUE)

CFLAGS ?= -O2
CFLAGS += -std=gnu11 -fPIC -Wall -I$(BUILD) -I$(VENDOR)/src $(shell pkg-config --cflags wayland-client)
LDLIBS := $(shell pkg-config --libs wayland-client)

LAYER := $(BUILD)/omarchy-bg-live-layer.so

all: $(LAYER)

$(BUILD):
	mkdir -p $@

$(BUILD)/%-client.h: | $(BUILD)
	wayland-scanner client-header $(filter %/$*.xml,$(XML)) $@

$(BUILD)/%.c: | $(BUILD)
	wayland-scanner private-code $(filter %/$*.xml,$(XML)) $@

$(LAYER): $(SOURCES) $(HEADERS)
	$(CC) $(CFLAGS) -shared -o $@ $(SOURCES) $(LDLIBS)

install: $(LAYER)
	install -Dm755 bin/omarchy-bg-live $(DESTDIR)$(PREFIX)/bin/omarchy-bg-live
	install -Dm755 $(LAYER) $(DESTDIR)$(PREFIX)/lib/omarchy-bg-live/omarchy-bg-live-layer.so
	mkdir -p $(DESTDIR)$(PREFIX)/share/omarchy-bg-live
	cp -r sources $(DESTDIR)$(PREFIX)/share/omarchy-bg-live/

uninstall:
	rm -rf $(DESTDIR)$(PREFIX)/bin/omarchy-bg-live $(DESTDIR)$(PREFIX)/lib/omarchy-bg-live $(DESTDIR)$(PREFIX)/share/omarchy-bg-live

test:
	@for test in test/*-test.sh; do bash "$$test" || exit 1; done

clean:
	rm -rf $(BUILD)

.PHONY: all install uninstall test clean
