// Waits for the user to come back, so a screensaver can end on the first
// mouse motion, click, scroll or key, whichever surface is on top.
//
// It asks the compositor for an input idle notification (ext_idle_notify_v1,
// version 2), which idle inhibitors do not mask, with the grace period as its
// timeout. Once the user has been idle that long it is armed, and the next
// activity ends it. So the input that crossed the idle threshold, or the click
// on "Preview", never dismisses the screensaver at once.
//
//   omarchy-ambient-dismiss [--grace <ms>]
//
// Prints "ready" once it is listening and "activity" when the user is back,
// then exits 0. Exits 1 when the compositor lacks the protocol or the
// connection is lost, so the caller never runs a screensaver it cannot end.

#include "ext-idle-notify-v1-client.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

static struct wl_seat* seat = NULL;
static struct ext_idle_notifier_v1* notifier = NULL;
static uint32_t notifier_version = 0;
static int armed = 0;

static void registry_global(void* data, struct wl_registry* registry, uint32_t id, const char* interface,
                            uint32_t version) {
    (void)data;
    if (strcmp(interface, wl_seat_interface.name) == 0 && !seat) {
        seat = wl_registry_bind(registry, id, &wl_seat_interface, 1);
    } else if (strcmp(interface, ext_idle_notifier_v1_interface.name) == 0 && !notifier) {
        notifier_version = version < 2 ? version : 2;
        notifier = wl_registry_bind(registry, id, &ext_idle_notifier_v1_interface, notifier_version);
    }
}

static void registry_global_remove(void* data, struct wl_registry* registry, uint32_t id) {
    (void)data, (void)registry, (void)id;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

static void idled(void* data, struct ext_idle_notification_v1* notification) {
    (void)data, (void)notification;
    armed = 1;
}

static void resumed(void* data, struct ext_idle_notification_v1* notification) {
    (void)data, (void)notification;
    if (armed) {
        puts("activity");
        fflush(stdout);
        exit(0);
    }
}

static const struct ext_idle_notification_v1_listener notification_listener = {
    .idled = idled,
    .resumed = resumed,
};

int main(int argc, char** argv) {
    long grace = 1000;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--grace") == 0 && i + 1 < argc) {
            grace = strtol(argv[++i], NULL, 10);
        } else {
            fprintf(stderr, "Usage: omarchy-ambient-dismiss [--grace <ms>]\n");
            return 1;
        }
    }
    // The compositor needs a timeout above zero.
    if (grace < 1) grace = 1;

    struct wl_display* display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "omarchy-ambient-dismiss: cannot connect to the Wayland display\n");
        return 1;
    }

    struct wl_registry* registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);

    if (!seat || !notifier) {
        fprintf(stderr, "omarchy-ambient-dismiss: the compositor lacks %s\n",
                seat ? "ext_idle_notify_v1" : "a seat");
        return 1;
    }

    // Version 1 only has the notification that idle inhibitors hold back.
    // The layer library stubs inhibitors in the programs it runs, so that is
    // still enough, if not as strict.
    struct ext_idle_notification_v1* notification =
        notifier_version >= 2 ? ext_idle_notifier_v1_get_input_idle_notification(notifier, grace, seat)
                              : ext_idle_notifier_v1_get_idle_notification(notifier, grace, seat);
    ext_idle_notification_v1_add_listener(notification, &notification_listener, NULL);
    if (wl_display_roundtrip(display) < 0) {
        fprintf(stderr, "omarchy-ambient-dismiss: the compositor refused the idle notification\n");
        return 1;
    }

    puts("ready");
    fflush(stdout);

    while (wl_display_dispatch(display) >= 0) {
    }
    fprintf(stderr, "omarchy-ambient-dismiss: lost the Wayland connection\n");
    return 1;
}
