PREFIX ?= /usr/local
DESTDIR ?=

BUILD := build
VENDOR := vendor/gtk4-layer-shell
PROTOCOLS := $(shell pkg-config --variable=pkgdatadir wayland-protocols)
LAYER_XML := $(VENDOR)/protocol/wlr-layer-shell-unstable-v1.xml \
	$(PROTOCOLS)/stable/xdg-shell/xdg-shell.xml \
	$(PROTOCOLS)/staging/ext-session-lock/ext-session-lock-v1.xml
DISMISS_XML := $(PROTOCOLS)/staging/ext-idle-notify/ext-idle-notify-v1.xml
XML := $(LAYER_XML) $(DISMISS_XML)

protocol_headers = $(patsubst %,$(BUILD)/%-client.h,$(basename $(notdir $(1))))
protocol_glue = $(patsubst %,$(BUILD)/%.c,$(basename $(notdir $(1))))

SOURCES := layer/omarchy-ambient-layer.c $(wildcard $(VENDOR)/src/*.c) $(call protocol_glue,$(LAYER_XML))
DISMISS_SOURCES := dismiss/omarchy-ambient-dismiss.c $(call protocol_glue,$(DISMISS_XML))

CFLAGS ?= -O2
CFLAGS += -std=gnu11 -fPIC -Wall -I$(BUILD) -I$(VENDOR)/src $(shell pkg-config --cflags wayland-client)
LDLIBS := $(shell pkg-config --libs wayland-client)

LAYER := $(BUILD)/omarchy-ambient-layer.so
DISMISS := $(BUILD)/omarchy-ambient-dismiss

all: $(LAYER) $(DISMISS)

$(BUILD):
	mkdir -p $@

$(BUILD)/%-client.h: | $(BUILD)
	wayland-scanner client-header $(filter %/$*.xml,$(XML)) $@

$(BUILD)/%.c: | $(BUILD)
	wayland-scanner private-code $(filter %/$*.xml,$(XML)) $@

$(LAYER): $(SOURCES) $(call protocol_headers,$(LAYER_XML))
	$(CC) $(CFLAGS) -shared -o $@ $(SOURCES) $(LDLIBS)

$(DISMISS): $(DISMISS_SOURCES) $(call protocol_headers,$(DISMISS_XML))
	$(CC) $(CFLAGS) -o $@ $(DISMISS_SOURCES) $(LDLIBS)

install: $(LAYER) $(DISMISS)
	install -Dm755 bin/omarchy-ambient $(DESTDIR)$(PREFIX)/bin/omarchy-ambient
	install -Dm755 $(LAYER) $(DESTDIR)$(PREFIX)/lib/omarchy-ambient/omarchy-ambient-layer.so
	install -Dm755 $(DISMISS) $(DESTDIR)$(PREFIX)/lib/omarchy-ambient/omarchy-ambient-dismiss
	mkdir -p $(DESTDIR)$(PREFIX)/share/omarchy-ambient
	cp -r sources $(DESTDIR)$(PREFIX)/share/omarchy-ambient/
	rm -rf $(DESTDIR)$(PREFIX)/bin/omarchy-bg-live $(DESTDIR)$(PREFIX)/lib/omarchy-bg-live $(DESTDIR)$(PREFIX)/share/omarchy-bg-live

uninstall:
	rm -rf $(DESTDIR)$(PREFIX)/bin/omarchy-ambient $(DESTDIR)$(PREFIX)/lib/omarchy-ambient $(DESTDIR)$(PREFIX)/share/omarchy-ambient

test:
	@for test in test/*-test.sh; do bash "$$test" || exit 1; done

clean:
	rm -rf $(BUILD)

.PHONY: all install uninstall test clean
