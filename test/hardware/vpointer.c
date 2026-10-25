// Sends one pointer event through a virtual pointer, so the screensaver's
// dismissal can be tried on a real compositor without touching the machine.
//
//   vpointer motion|click|scroll

#include "wlr-virtual-pointer-unstable-v1-client.h"

#include <linux/input-event-codes.h>
#include <stdio.h>
#include <string.h>
#include <wayland-client.h>

static struct zwlr_virtual_pointer_manager_v1* manager = NULL;

static void global(void* data, struct wl_registry* registry, uint32_t id, const char* interface, uint32_t version) {
    (void)data, (void)version;
    if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0) {
        manager = wl_registry_bind(registry, id, &zwlr_virtual_pointer_manager_v1_interface, 1);
    }
}

static void global_remove(void* data, struct wl_registry* registry, uint32_t id) {
    (void)data, (void)registry, (void)id;
}

static const struct wl_registry_listener listener = {.global = global, .global_remove = global_remove};

int main(int argc, char** argv) {
    if (argc != 2) {
        fprintf(stderr, "Usage: vpointer motion|click|scroll\n");
        return 1;
    }
    struct wl_display* display = wl_display_connect(NULL);
    if (!display) return 1;
    struct wl_registry* registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &listener, NULL);
    wl_display_roundtrip(display);
    if (!manager) {
        fprintf(stderr, "vpointer: no zwlr_virtual_pointer_manager_v1\n");
        return 1;
    }

    struct zwlr_virtual_pointer_v1* pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, NULL);
    if (strcmp(argv[1], "motion") == 0) {
        zwlr_virtual_pointer_v1_motion(pointer, 0, wl_fixed_from_int(5), wl_fixed_from_int(5));
    } else if (strcmp(argv[1], "click") == 0) {
        zwlr_virtual_pointer_v1_button(pointer, 0, BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED);
        zwlr_virtual_pointer_v1_frame(pointer);
        zwlr_virtual_pointer_v1_button(pointer, 1, BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED);
    } else if (strcmp(argv[1], "scroll") == 0) {
        zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_WHEEL);
        zwlr_virtual_pointer_v1_axis(pointer, 0, WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_int(10));
    } else {
        fprintf(stderr, "vpointer: unknown event %s\n", argv[1]);
        return 1;
    }
    zwlr_virtual_pointer_v1_frame(pointer);
    zwlr_virtual_pointer_v1_destroy(pointer);
    wl_display_roundtrip(display);
    return 0;
}
