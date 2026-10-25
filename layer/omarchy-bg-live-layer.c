// Preloaded into a program so its first window becomes live content: a layer
// surface stretched over one output, either behind every window and never
// taking keyboard focus (a background), or over everything with the keyboard
// to itself (a screensaver).
//
// It builds on gtk4-layer-shell's preload (vendor/gtk4-layer-shell) and adds
// what a background needs that the stock preload lacks:
//
//   OMARCHY_BG_LIVE_OUTPUT     name of the output to cover (eDP-1, DP-2, ...);
//                              unset means the compositor's choice
//   OMARCHY_BG_LIVE_NAMESPACE  layer namespace, omarchy-bg-live by default
//   OMARCHY_BG_LIVE_LAYER      bottom (default), background, top or overlay
//   OMARCHY_BG_LIVE_KEYBOARD   none (default), exclusive or on_demand
//
// SDL 3 also exports every toplevel it creates through xdg-foreign, which a
// layer surface cannot be, and the compositor then drops the connection. The
// export is answered with a stub here so SDL programs (emulators, games) run.
//
// Programs like SDL and mpv also inhibit idle while they show something. Live
// content must not keep the screen awake, hold off the screensaver or the
// lock, so idle inhibitors are answered with a stub as well. So is text input:
// SDL enables it whenever it gets the keyboard, which wakes the input method,
// and Hyprland takes the input method's reply for user activity. That ended a
// screensaver each time a program in it took the keyboard.
//
// The output handed to the compositor must be one the program bound itself:
// the compositor names it in wl_surface.enter, and a program like mpv crashes
// on an output it never saw. So the program's own output binds are recorded,
// and a private bind is only used to learn which global carries the name.

#include "layer-surface.h"
#include "libwayland-shim.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

#define MAX_OUTPUTS 32

struct output_search {
    const char* name;
    uint32_t found; // the matching output's global name, 0 if none
    struct wl_output* bound[MAX_OUTPUTS];
    uint32_t globals[MAX_OUTPUTS];
    int count;
};

// The outputs the program bound, by global name.
struct program_output {
    uint32_t global;
    struct wl_proxy* proxy;
};

static struct output_search search;
static struct program_output program_outputs[MAX_OUTPUTS];
static int program_output_count = 0;
static bool searching = false;
static bool forwarding_bind = false;
static bool created = false;

static void output_geometry(void* data, struct wl_output* output, int32_t x, int32_t y, int32_t width_mm,
                            int32_t height_mm, int32_t subpixel, const char* make, const char* model,
                            int32_t transform) {
    (void)data, (void)output, (void)x, (void)y, (void)width_mm, (void)height_mm, (void)subpixel, (void)make,
        (void)model, (void)transform;
}

static void output_mode(void* data, struct wl_output* output, uint32_t flags, int32_t width, int32_t height,
                        int32_t refresh) {
    (void)data, (void)output, (void)flags, (void)width, (void)height, (void)refresh;
}

static void output_done(void* data, struct wl_output* output) {
    (void)data, (void)output;
}

static void output_scale(void* data, struct wl_output* output, int32_t factor) {
    (void)data, (void)output, (void)factor;
}

static void output_name(void* data, struct wl_output* output, const char* name) {
    struct output_search* self = data;
    for (int i = 0; i < self->count; i++) {
        if (self->bound[i] == output && !self->found && strcmp(name, self->name) == 0) {
            self->found = self->globals[i];
        }
    }
}

static void output_description(void* data, struct wl_output* output, const char* description) {
    (void)data, (void)output, (void)description;
}

static const struct wl_output_listener output_listener = {
    .geometry = output_geometry,
    .mode = output_mode,
    .done = output_done,
    .scale = output_scale,
    .name = output_name,
    .description = output_description,
};

static void registry_global(void* data, struct wl_registry* registry, uint32_t id, const char* interface,
                            uint32_t version) {
    struct output_search* self = data;
    // Output names arrived in wl_output version 4.
    if (strcmp(interface, wl_output_interface.name) == 0 && version >= 4 && self->count < MAX_OUTPUTS) {
        struct wl_output* output = wl_registry_bind(registry, id, &wl_output_interface, 4);
        wl_output_add_listener(output, &output_listener, self);
        self->globals[self->count] = id;
        self->bound[self->count++] = output;
    }
}

static void registry_global_remove(void* data, struct wl_registry* registry, uint32_t id) {
    (void)data, (void)registry, (void)id;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

// Learns which global is the named output from private binds on a private
// queue, which the program never sees, then hands back the program's own
// proxy for that global.
static struct wl_output* find_output(struct wl_display* display, const char* name) {
    struct wl_event_queue* queue = wl_display_create_queue(display);
    struct wl_display* wrapper = wl_proxy_create_wrapper(display);
    wl_proxy_set_queue((struct wl_proxy*)wrapper, queue);

    searching = true;
    search.name = name;
    struct wl_registry* registry = wl_display_get_registry(wrapper);
    wl_registry_add_listener(registry, &registry_listener, &search);
    wl_display_roundtrip_queue(display, queue); // globals, and the binds they cause
    wl_display_roundtrip_queue(display, queue); // the bound outputs' names
    searching = false;

    for (int i = 0; i < search.count; i++) {
        wl_output_release(search.bound[i]);
    }
    wl_registry_destroy(registry);
    wl_proxy_wrapper_destroy(wrapper);
    wl_event_queue_destroy(queue);

    if (!search.found) {
        fprintf(stderr, "omarchy-bg-live-layer: no output named %s, using the compositor's choice\n", name);
        return NULL;
    }
    for (int i = 0; i < program_output_count; i++) {
        if (program_outputs[i].global == search.found) {
            return (struct wl_output*)program_outputs[i].proxy;
        }
    }
    fprintf(stderr, "omarchy-bg-live-layer: the program never bound %s, using the compositor's choice\n", name);
    return NULL;
}

// wl_registry.bind of a wl_output: forward it, and remember which global the
// program's proxy stands for.
static bool record_output_bind(void* data, struct wl_proxy* proxy, uint32_t opcode,
                               const struct wl_interface* created_interface, uint32_t created_version, uint32_t flags,
                               union wl_argument* args, struct wl_proxy** ret_proxy) {
    (void)data;
    if (searching || forwarding_bind || !created_interface || strcmp(created_interface->name, wl_output_interface.name) != 0) {
        return false;
    }

    forwarding_bind = true;
    *ret_proxy = wl_proxy_marshal_array_flags(proxy, opcode, created_interface, created_version, flags, args);
    forwarding_bind = false;

    if (*ret_proxy && program_output_count < MAX_OUTPUTS) {
        program_outputs[program_output_count++] = (struct program_output){args[0].u, *ret_proxy};
    }
    return true;
}

static const char* env_or(const char* name, const char* fallback) {
    const char* value = getenv(name);
    return value && *value ? value : fallback;
}

static enum zwlr_layer_shell_v1_layer layer_from_env(void) {
    const char* layer = env_or("OMARCHY_BG_LIVE_LAYER", "bottom");
    if (strcmp(layer, "background") == 0) return ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND;
    if (strcmp(layer, "top") == 0) return ZWLR_LAYER_SHELL_V1_LAYER_TOP;
    if (strcmp(layer, "overlay") == 0) return ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY;
    return ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM;
}

static enum zwlr_layer_surface_v1_keyboard_interactivity keyboard_from_env(void) {
    const char* keyboard = env_or("OMARCHY_BG_LIVE_KEYBOARD", "none");
    if (strcmp(keyboard, "exclusive") == 0) return ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE;
    if (strcmp(keyboard, "on_demand") == 0) return ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_ON_DEMAND;
    return ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE;
}

static struct geom_size_t no_preferred_size(struct layer_surface_t* surface) {
    (void)surface;
    return (struct geom_size_t){0};
}

static struct layer_surface_t* make_background(struct wl_surface* wl_surface) {
    // Only the program's first window becomes the background; any later one
    // (a dialog, a second window) stays an ordinary window.
    if (created) {
        return NULL;
    }
    created = true;

    struct layer_surface_t* self = malloc(sizeof(struct layer_surface_t));
    *self = layer_surface_make();
    self->get_preferred_size = no_preferred_size;
    layer_surface_set_name_space(self, env_or("OMARCHY_BG_LIVE_NAMESPACE", "omarchy-bg-live"));
    layer_surface_set_layer(self, layer_from_env());
    layer_surface_set_anchor(self, (struct geom_edges_t){.left = true, .right = true, .top = true, .bottom = true});
    layer_surface_set_exclusive_zone(self, -1);
    layer_surface_set_keyboard_mode(self, keyboard_from_env());

    const char* output = getenv("OMARCHY_BG_LIVE_OUTPUT");
    if (output && *output) {
        layer_surface_set_output(self, find_output(libwayland_shim_proxy_get_display((struct wl_proxy*)wl_surface), output));
    }
    return self;
}

// zxdg_exporter_v2.export_toplevel: hand back a stub zxdg_exported_v2 that
// never gets a handle, as a compositor without xdg-foreign would. The same
// stub answers zwp_idle_inhibit_manager_v1.create_inhibitor and
// zwp_text_input_manager_v3.get_text_input, so neither reaches the compositor.
static bool stub_object(void* data, struct wl_proxy* proxy, uint32_t opcode, const struct wl_interface* created_interface,
                        uint32_t created_version, uint32_t flags, union wl_argument* args, struct wl_proxy** ret_proxy) {
    (void)data, (void)opcode, (void)flags, (void)args;
    *ret_proxy = libwayland_shim_create_client_proxy(proxy, created_interface, created_version, NULL, NULL, NULL);
    return true;
}

// Hooks match requests by interface name, so the interface needs no more
// than that.
static const struct wl_interface zxdg_exporter_v2_interface = {.name = "zxdg_exporter_v2"};
#define ZXDG_EXPORTER_V2_EXPORT_TOPLEVEL 1
static const struct wl_interface zwp_idle_inhibit_manager_v1_interface = {.name = "zwp_idle_inhibit_manager_v1"};
#define ZWP_IDLE_INHIBIT_MANAGER_V1_CREATE_INHIBITOR 1
static const struct wl_interface zwp_text_input_manager_v3_interface = {.name = "zwp_text_input_manager_v3"};
#define ZWP_TEXT_INPUT_MANAGER_V3_GET_TEXT_INPUT 1

__attribute__((constructor)) static void setup(void) {
    layer_surface_install_hook(make_background);
    libwayland_shim_install_request_hook(&zxdg_exporter_v2_interface, ZXDG_EXPORTER_V2_EXPORT_TOPLEVEL, stub_object, NULL);
    libwayland_shim_install_request_hook(&zwp_idle_inhibit_manager_v1_interface,
                                         ZWP_IDLE_INHIBIT_MANAGER_V1_CREATE_INHIBITOR, stub_object, NULL);
    libwayland_shim_install_request_hook(&zwp_text_input_manager_v3_interface, ZWP_TEXT_INPUT_MANAGER_V3_GET_TEXT_INPUT,
                                         stub_object, NULL);
    libwayland_shim_install_request_hook(&wl_registry_interface, WL_REGISTRY_BIND, record_output_bind, NULL);
}
