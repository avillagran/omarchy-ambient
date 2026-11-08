PREFIX ?= /usr/local
DESTDIR ?=
# The selector plugin loads from a directory named after it: the shell caches
# QML by path, so a new release must not reuse the old one.
VERSION ?= 0.6.1

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

SELECTOR := contrib/background-selector
NATIVE_SRC := $(SELECTOR)/live-preview/native/AmbientCells
NATIVE := $(BUILD)/native/libambientcells.so
QT_MODULES := Qt6Quick Qt6Qml Qt6Gui
QT_LIBEXEC ?= /usr/lib/qt6
HAVE_QT := $(shell pkg-config --exists $(QT_MODULES) 2>/dev/null && [ -x $(QT_LIBEXEC)/moc ] && [ -x $(QT_LIBEXEC)/rcc ] && [ -x $(QT_LIBEXEC)/bin/qsb ] && echo yes)
PLUGIN_DIR = $(DESTDIR)$(PREFIX)/share/omarchy-ambient/plugin

all: $(LAYER) $(DISMISS) native

$(BUILD):
	mkdir -p $@

$(BUILD)/%-client.h: | $(BUILD)
	wayland-scanner client-header $(filter %/$*.xml,$(XML)) $@

$(BUILD)/%.c: | $(BUILD)
	wayland-scanner private-code $(filter %/$*.xml,$(XML)) $@

$(LAYER): $(SOURCES) $(call protocol_headers,$(LAYER_XML))
	$(CC) $(CFLAGS) $(LDFLAGS) -shared -o $@ $(SOURCES) $(LDLIBS)

$(DISMISS): $(DISMISS_SOURCES) $(call protocol_headers,$(DISMISS_XML))
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(DISMISS_SOURCES) $(LDLIBS)

# The GPU painter for the carousel previews. Without Qt's development files
# and shader tools the carousel draws them with Canvas instead.
ifeq ($(HAVE_QT),yes)
native: $(NATIVE)
else
native:
	@echo "No Qt 6 development files or shader tools: the selector previews use Canvas" >&2
endif

$(NATIVE): $(NATIVE_SRC)/cellpreview.cpp $(NATIVE_SRC)/cells.vert $(NATIVE_SRC)/cells.frag $(NATIVE_SRC)/cells.qrc | $(BUILD)
	rm -rf $(BUILD)/native-src && mkdir -p $(BUILD)/native-src $(BUILD)/native
	cp $(NATIVE_SRC)/cellpreview.cpp $(NATIVE_SRC)/cells.vert $(NATIVE_SRC)/cells.frag $(NATIVE_SRC)/cells.qrc $(BUILD)/native-src/
	cd $(BUILD)/native-src && for stage in vert frag; do $(QT_LIBEXEC)/bin/qsb --glsl "100 es,120,150" -o cells.$$stage.qsb cells.$$stage || exit 1; done
	cd $(BUILD)/native-src && $(QT_LIBEXEC)/rcc -name ambientcells cells.qrc -o qrc_cells.cpp
	$(QT_LIBEXEC)/moc $(shell pkg-config --cflags $(QT_MODULES) 2>/dev/null) $(BUILD)/native-src/cellpreview.cpp -o $(BUILD)/native-src/cellpreview.moc
	$(CXX) $(CXXFLAGS) -O2 -std=c++17 -fPIC -shared -I$(BUILD)/native-src $(BUILD)/native-src/cellpreview.cpp $(BUILD)/native-src/qrc_cells.cpp -o $@ $(LDFLAGS) $(shell pkg-config --cflags --libs $(QT_MODULES) 2>/dev/null)

install: install-core install-selector

install-core: $(LAYER) $(DISMISS)
	install -Dm755 bin/omarchy-ambient $(DESTDIR)$(PREFIX)/bin/omarchy-ambient
	install -Dm755 $(LAYER) $(DESTDIR)$(PREFIX)/lib/omarchy-ambient/omarchy-ambient-layer.so
	install -Dm755 $(DISMISS) $(DESTDIR)$(PREFIX)/lib/omarchy-ambient/omarchy-ambient-dismiss
	mkdir -p $(DESTDIR)$(PREFIX)/share/omarchy-ambient
	cp -r sources $(DESTDIR)$(PREFIX)/share/omarchy-ambient/
	# What omarchy-bg-live installed. Not all of share/omarchy-bg-live: with
	# PREFIX=~/.local that is where the sources keep their downloads too.
	rm -rf $(DESTDIR)$(PREFIX)/bin/omarchy-bg-live $(DESTDIR)$(PREFIX)/lib/omarchy-bg-live $(DESTDIR)$(PREFIX)/share/omarchy-bg-live/sources

# The background selector: a command, the Omarchy shell plugin it opens, and
# the posters of the scenes. omarchy-ambient selector enable links the plugin
# for the user.
install-selector: native | $(BUILD)
	install -Dm755 $(SELECTOR)/background_selector.py $(DESTDIR)$(PREFIX)/lib/omarchy-ambient/selector/background_selector.py
	install -Dm755 $(SELECTOR)/run-preview.py $(DESTDIR)$(PREFIX)/lib/omarchy-ambient/selector/run-preview.py
	install -Dm644 $(SELECTOR)/catalog.json $(DESTDIR)$(PREFIX)/lib/omarchy-ambient/selector/catalog.json
	# The renderer runs the previews under this name.
	ln -sfn $(PREFIX)/bin/omarchy-ttfx-layer $(DESTDIR)$(PREFIX)/lib/omarchy-ambient/selector/ttfx-ambient-preview
	mkdir -p $(DESTDIR)$(PREFIX)/share/omarchy-ambient/posters
	install -m644 $(SELECTOR)/posters/* $(DESTDIR)$(PREFIX)/share/omarchy-ambient/posters/
	printf '%s\n' '#!/bin/bash' \
		'# The background selector of omarchy-ambient, with the files this package installed.' \
		'export OMARCHY_AMBIENT_BIN=$(PREFIX)/bin/omarchy-ambient' \
		'export OMARCHY_AMBIENT_POSTERS=$(PREFIX)/share/omarchy-ambient/posters' \
		'export OMARCHY_AMBIENT_SOURCES=$(PREFIX)/share/omarchy-ambient/sources' \
		'exec python3 $(PREFIX)/lib/omarchy-ambient/selector/background_selector.py "$$@"' >$(BUILD)/omarchy-ambient-select
	install -Dm755 $(BUILD)/omarchy-ambient-select $(DESTDIR)$(PREFIX)/bin/omarchy-ambient-select
	rm -rf $(PLUGIN_DIR) && mkdir -p $(PLUGIN_DIR)/v$(VERSION)/bin
	install -m644 $(SELECTOR)/live-preview/*.qml $(SELECTOR)/live-preview/*.js $(PLUGIN_DIR)/v$(VERSION)/
	install -m755 $(SELECTOR)/live-preview/bin/list.sh $(PLUGIN_DIR)/v$(VERSION)/bin/list.sh
	printf '%s\n' '#!/bin/bash' 'exec $(PREFIX)/bin/omarchy-ambient-select "$$@"' >$(PLUGIN_DIR)/v$(VERSION)/bin/select
	chmod 755 $(PLUGIN_DIR)/v$(VERSION)/bin/select
	if [ -f $(NATIVE) ]; then \
		install -Dm755 $(NATIVE) $(PLUGIN_DIR)/v$(VERSION)/native/AmbientCells/libambientcells.so; \
		install -m644 $(NATIVE_SRC)/qmldir $(PLUGIN_DIR)/v$(VERSION)/native/AmbientCells/qmldir; \
	fi
	jq --arg v $(VERSION) '.version = $$v | .entryPoints.service = "v\($$v)/Service.qml"' \
		$(SELECTOR)/live-preview/manifest.json >$(PLUGIN_DIR)/manifest.json

uninstall:
	rm -rf $(DESTDIR)$(PREFIX)/bin/omarchy-ambient $(DESTDIR)$(PREFIX)/bin/omarchy-ambient-select $(DESTDIR)$(PREFIX)/lib/omarchy-ambient $(DESTDIR)$(PREFIX)/share/omarchy-ambient

test:
	@for test in test/*-test.sh; do bash "$$test" || exit 1; done

clean:
	rm -rf $(BUILD)

.PHONY: all native install install-core install-selector uninstall test clean
