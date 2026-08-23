#include <time.h>
/*
 * evdev-bridge: Reads evdev events from Sunshine's virtual input devices
 * and injects them into Hyprland via Wayland protocols:
 *   - zwlr_virtual_pointer_manager_v1 for mouse
 *   - zwp_virtual_keyboard_v1 for keyboard
 *
 * This is needed because Hyprland in an LXC container has no libinput
 * backend, so kernel /dev/input devices are invisible to it.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <dirent.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <linux/input.h>
#include <linux/input-event-codes.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>

#include "protocols/wlr-virtual-pointer-unstable-v1-client-protocol.h"
#include "protocols/virtual-keyboard-unstable-v1-client-protocol.h"

/* Globals */
static struct wl_display *display;
static struct wl_registry *registry;
static struct wl_seat *seat;
static struct zwlr_virtual_pointer_manager_v1 *pointer_manager;
static struct zwp_virtual_keyboard_manager_v1 *keyboard_manager;
static struct zwlr_virtual_pointer_v1 *vpointer;
static struct zwp_virtual_keyboard_v1 *vkeyboard;
static struct wl_output *output;

static int screen_w = 1920;
static int screen_h = 1200;
static volatile int running = 1;

/* Device paths */
static char kbd_path[256];
static char rel_mouse_path[256];
static char abs_mouse_path[256];

static int kbd_fd = -1;
static int rel_mouse_fd = -1;
static int abs_mouse_fd = -1;

/* Get evdev device name */
static int get_device_name(int fd, char *buf, size_t len) {
    if (ioctl(fd, EVIOCGNAME(len), buf) < 0)
        return -1;
    return 0;
}

/* Find a /dev/input/event* device by name prefix */
static int find_device(const char *name_prefix, char *out_path, size_t path_len) {
    DIR *dir = opendir("/dev/input");
    if (!dir) return -1;

    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        if (strncmp(ent->d_name, "event", 5) != 0) continue;

        char path[256];
        snprintf(path, sizeof(path), "/dev/input/%s", ent->d_name);

        int fd = open(path, O_RDONLY | O_NONBLOCK);
        if (fd < 0) continue;

        char name[256] = {0};
        get_device_name(fd, name, sizeof(name));
        close(fd);

        if (strncmp(name, name_prefix, strlen(name_prefix)) == 0) {
            /* For "Mouse passthrough" vs "Mouse passthrough (absolute)" */
            if (strcmp(name_prefix, "Mouse passthrough") == 0 &&
                strstr(name, "absolute") != NULL) {
                continue; /* Skip absolute, we want relative */
            }
            snprintf(out_path, path_len, "%s", path);
            closedir(dir);
            fprintf(stderr, "[bridge] Found '%s' at %s\n", name, path);
            return 0;
        }
    }
    closedir(dir);
    return -1;
}

/* Create an anonymous file for the keymap */
static int create_anon_file(size_t size) {
    char name[] = "/tmp/evdev-bridge-keymap-XXXXXX";
    int fd = mkstemp(name);
    if (fd < 0) return -1;
    unlink(name);
    if (ftruncate(fd, size) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

/* Registry listener */
static void registry_global(void *data, struct wl_registry *reg,
                            uint32_t name, const char *interface, uint32_t version) {
    (void)data;
    if (strcmp(interface, wl_seat_interface.name) == 0) {
        seat = wl_registry_bind(reg, name, &wl_seat_interface, 1);
        fprintf(stderr, "[bridge] Bound wl_seat (v%u)\n", version);
    } else if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0) {
        /* MUST bind at version 2 to use create_virtual_pointer_with_output */
        uint32_t bind_ver = version < 2 ? version : 2;
        pointer_manager = wl_registry_bind(reg, name,
            &zwlr_virtual_pointer_manager_v1_interface, bind_ver);
        fprintf(stderr, "[bridge] Bound zwlr_virtual_pointer_manager_v1 (v%u, bound v%u)\n",
                version, bind_ver);
    } else if (strcmp(interface, zwp_virtual_keyboard_manager_v1_interface.name) == 0) {
        keyboard_manager = wl_registry_bind(reg, name,
            &zwp_virtual_keyboard_manager_v1_interface, 1);
        fprintf(stderr, "[bridge] Bound zwp_virtual_keyboard_manager_v1 (v%u)\n", version);
    } else if (strcmp(interface, wl_output_interface.name) == 0 && !output) {
        output = wl_registry_bind(reg, name, &wl_output_interface, 1);
        fprintf(stderr, "[bridge] Bound wl_output (v%u)\n", version);
    }
}

static void registry_global_remove(void *data, struct wl_registry *reg, uint32_t name) {
    (void)data; (void)reg; (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

/* Set up the virtual keyboard with a keymap */
static int setup_keyboard(void) {
    struct xkb_context *ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (!ctx) {
        fprintf(stderr, "[bridge] Failed to create xkb context\n");
        return -1;
    }

    struct xkb_rule_names names = {
        .rules = "evdev",
        .model = "pc105",
        .layout = "us",
        .variant = NULL,
        .options = NULL,
    };

    struct xkb_keymap *keymap = xkb_keymap_new_from_names(ctx, &names,
        XKB_KEYMAP_COMPILE_NO_FLAGS);
    if (!keymap) {
        fprintf(stderr, "[bridge] Failed to create keymap\n");
        xkb_context_unref(ctx);
        return -1;
    }

    char *keymap_str = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
    if (!keymap_str) {
        fprintf(stderr, "[bridge] Failed to get keymap string\n");
        xkb_keymap_unref(keymap);
        xkb_context_unref(ctx);
        return -1;
    }

    size_t keymap_size = strlen(keymap_str) + 1;
    int fd = create_anon_file(keymap_size);
    if (fd < 0) {
        fprintf(stderr, "[bridge] Failed to create keymap file\n");
        free(keymap_str);
        xkb_keymap_unref(keymap);
        xkb_context_unref(ctx);
        return -1;
    }

    char *map = mmap(NULL, keymap_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) {
        close(fd);
        free(keymap_str);
        xkb_keymap_unref(keymap);
        xkb_context_unref(ctx);
        return -1;
    }
    memcpy(map, keymap_str, keymap_size);
    munmap(map, keymap_size);

    zwp_virtual_keyboard_v1_keymap(vkeyboard,
        WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, keymap_size);

    close(fd);
    free(keymap_str);
    xkb_keymap_unref(keymap);
    xkb_context_unref(ctx);

    fprintf(stderr, "[bridge] Keyboard keymap uploaded (%zu bytes, us/pc105)\n", keymap_size);
    return 0;
}

static uint32_t get_time_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

/* Check Wayland connection for errors */
static int check_display_error(void) {
    int err = wl_display_get_error(display);
    if (err) {
        fprintf(stderr, "[bridge] Wayland display error: %d (%s)\n", err, strerror(err));
        if (err == EPROTO) {
            uint32_t id;
            uint32_t code;
            const struct wl_interface *iface;
            code = wl_display_get_protocol_error(display, &iface, &id);
            fprintf(stderr, "[bridge] Protocol error: object %u, interface '%s', code %u\n",
                    id, iface ? iface->name : "unknown", code);
        }
        return -1;
    }
    return 0;
}

/* Scroll accumulator: Sunshine sends REL_WHEEL_HI_RES in 1/120th notch units.
 * We accumulate and emit a discrete scroll step per 120 units. */
static int32_t scroll_accum_v = 0;
static int32_t scroll_accum_h = 0;
static int scroll_pending = 0;

/* Process mouse events */
static void handle_mouse_event(struct input_event *ev) {
    uint32_t t = get_time_ms();

    switch (ev->type) {
    case EV_REL:
        switch (ev->code) {
        case REL_X:
            zwlr_virtual_pointer_v1_motion(vpointer, t,
                wl_fixed_from_int(ev->value), 0);
            break;
        case REL_Y:
            zwlr_virtual_pointer_v1_motion(vpointer, t,
                0, wl_fixed_from_int(ev->value));
            break;
        case REL_WHEEL:
            /* Discrete wheel event — send directly */
            zwlr_virtual_pointer_v1_axis_source(vpointer,
                WL_POINTER_AXIS_SOURCE_WHEEL);
            zwlr_virtual_pointer_v1_axis(vpointer, t,
                WL_POINTER_AXIS_VERTICAL_SCROLL,
                wl_fixed_from_int(-ev->value * 15));
            zwlr_virtual_pointer_v1_frame(vpointer);
            break;
        case REL_HWHEEL:
            zwlr_virtual_pointer_v1_axis_source(vpointer,
                WL_POINTER_AXIS_SOURCE_WHEEL);
            zwlr_virtual_pointer_v1_axis(vpointer, t,
                WL_POINTER_AXIS_HORIZONTAL_SCROLL,
                wl_fixed_from_int(ev->value * 15));
            zwlr_virtual_pointer_v1_frame(vpointer);
            break;
#ifndef REL_WHEEL_HI_RES
#define REL_WHEEL_HI_RES 11
#endif
#ifndef REL_HWHEEL_HI_RES
#define REL_HWHEEL_HI_RES 12
#endif
        case REL_WHEEL_HI_RES:
            /* Accumulate hi-res scroll and emit when we have a full notch (120 units) */
            scroll_accum_v += ev->value;
            scroll_pending = 1;
            break;
        case REL_HWHEEL_HI_RES:
            scroll_accum_h += ev->value;
            scroll_pending = 1;
            break;
        }
        break;

    case EV_KEY:
        if (ev->code >= BTN_LEFT && ev->code <= BTN_TASK) {
            uint32_t button;
            switch (ev->code) {
            case BTN_LEFT:    button = BTN_LEFT;   break;
            case BTN_RIGHT:   button = BTN_RIGHT;  break;
            case BTN_MIDDLE:  button = BTN_MIDDLE; break;
            case BTN_SIDE:    button = BTN_SIDE;   break;
            case BTN_EXTRA:   button = BTN_EXTRA;  break;
            case BTN_FORWARD: button = BTN_FORWARD; break;
            case BTN_BACK:    button = BTN_BACK;   break;
            default: button = ev->code; break;
            }
            zwlr_virtual_pointer_v1_button(vpointer, t, button,
                ev->value ? WL_POINTER_BUTTON_STATE_PRESSED :
                           WL_POINTER_BUTTON_STATE_RELEASED);
        }
        break;

    case EV_SYN:
        if (ev->code == SYN_REPORT) {
            /* Flush accumulated hi-res scroll on SYN_REPORT */
            if (scroll_pending) {
                if (scroll_accum_v != 0) {
                    /* Convert accumulated 1/120th units to pixel scroll.
                     * Each 120 units = 1 notch = ~15 pixels of scroll.
                     * Send proportional amounts for smooth scrolling. */
                    double pixels_v = (double)(-scroll_accum_v) / 120.0 * 15.0;
                    zwlr_virtual_pointer_v1_axis_source(vpointer,
                        WL_POINTER_AXIS_SOURCE_WHEEL);
                    zwlr_virtual_pointer_v1_axis(vpointer, t,
                        WL_POINTER_AXIS_VERTICAL_SCROLL,
                        wl_fixed_from_double(pixels_v));
                    /* Also send discrete step for apps that need it */
                    int32_t discrete_v = scroll_accum_v / 120;
                    if (discrete_v != 0) {
                        zwlr_virtual_pointer_v1_axis_discrete(vpointer, t,
                            WL_POINTER_AXIS_VERTICAL_SCROLL,
                            wl_fixed_from_double(pixels_v),
                            -discrete_v);
                    }
                    scroll_accum_v %= 120; /* Keep remainder */
                }
                if (scroll_accum_h != 0) {
                    double pixels_h = (double)(scroll_accum_h) / 120.0 * 15.0;
                    zwlr_virtual_pointer_v1_axis_source(vpointer,
                        WL_POINTER_AXIS_SOURCE_WHEEL);
                    zwlr_virtual_pointer_v1_axis(vpointer, t,
                        WL_POINTER_AXIS_HORIZONTAL_SCROLL,
                        wl_fixed_from_double(pixels_h));
                    int32_t discrete_h = scroll_accum_h / 120;
                    if (discrete_h != 0) {
                        zwlr_virtual_pointer_v1_axis_discrete(vpointer, t,
                            WL_POINTER_AXIS_HORIZONTAL_SCROLL,
                            wl_fixed_from_double(pixels_h),
                            discrete_h);
                    }
                    scroll_accum_h %= 120;
                }
                scroll_pending = 0;
            }
            zwlr_virtual_pointer_v1_frame(vpointer);
        }
        break;
    }
}

/* Process absolute mouse events */
static void handle_abs_mouse_event(struct input_event *ev) {
    static int32_t ax = -1, ay = -1;
    uint32_t t = get_time_ms();

    switch (ev->type) {
    case EV_ABS:
        switch (ev->code) {
        case ABS_X:
            ax = ev->value;
            break;
        case ABS_Y:
            ay = ev->value;
            break;
        }
        break;

    case EV_KEY:
        if (ev->code >= BTN_LEFT && ev->code <= BTN_TASK) {
            uint32_t button;
            switch (ev->code) {
            case BTN_LEFT:    button = BTN_LEFT;   break;
            case BTN_RIGHT:   button = BTN_RIGHT;  break;
            case BTN_MIDDLE:  button = BTN_MIDDLE; break;
            default: button = ev->code; break;
            }
            zwlr_virtual_pointer_v1_button(vpointer, t, button,
                ev->value ? WL_POINTER_BUTTON_STATE_PRESSED :
                           WL_POINTER_BUTTON_STATE_RELEASED);
        }
        break;

    case EV_SYN:
        if (ev->code == SYN_REPORT) {
            if (ax >= 0 && ay >= 0) {
                /* Sunshine absolute range is 0-65535, map to screen */
                zwlr_virtual_pointer_v1_motion_absolute(vpointer, t,
                    (uint32_t)ax, (uint32_t)ay, 65535, 65535);
                ax = -1;
                ay = -1;
            }
            zwlr_virtual_pointer_v1_frame(vpointer);
        }
        break;
    }
}

/* Modifier state tracking */
static uint32_t mod_depressed = 0;

/* XKB modifier bit masks (standard values) */
#define MOD_SHIFT_BIT   (1 << 0)
#define MOD_CAPSLOCK_BIT (1 << 1)
#define MOD_CTRL_BIT    (1 << 2)
#define MOD_ALT_BIT     (1 << 3)
#define MOD_NUMLOCK_BIT (1 << 4)
#define MOD_MOD3_BIT    (1 << 5)
#define MOD_SUPER_BIT   (1 << 6)
#define MOD_MOD5_BIT    (1 << 7)

static uint32_t evdev_to_mod_bit(uint32_t code) {
    switch (code) {
    case KEY_LEFTSHIFT:
    case KEY_RIGHTSHIFT:
        return MOD_SHIFT_BIT;
    case KEY_LEFTCTRL:
    case KEY_RIGHTCTRL:
        return MOD_CTRL_BIT;
    case KEY_LEFTALT:
    case KEY_RIGHTALT:
        return MOD_ALT_BIT;
    case KEY_LEFTMETA:
    case KEY_RIGHTMETA:
        return MOD_SUPER_BIT;
    case KEY_CAPSLOCK:
        return MOD_CAPSLOCK_BIT;
    case KEY_NUMLOCK:
        return MOD_NUMLOCK_BIT;
    default:
        return 0;
    }
}

/* Key debounce tracking */
#define MAX_KEYS 256
static uint32_t key_last_press_time[MAX_KEYS]; /* timestamp of last press in ms */
#define KEY_DEBOUNCE_MS 100 /* ignore re-press within this window */

/* Process keyboard events */
static void handle_keyboard_event(struct input_event *ev) {
    if (ev->type == EV_KEY) {
        uint32_t t = get_time_ms();
        /* ev->value: 0=release, 1=press, 2=repeat */
        if (ev->value == 2) return; /* skip autorepeat, compositor handles it */

        /* Time-based debounce: ignore rapid re-press of the same key */
        if (ev->code < MAX_KEYS && ev->value == 1) {
            uint32_t elapsed = t - key_last_press_time[ev->code];
            if (elapsed < KEY_DEBOUNCE_MS) {
                fprintf(stderr, "[bridge] DEBOUNCE: code=%u elapsed=%ums < %ums, DROPPED\n",
                        ev->code, elapsed, KEY_DEBOUNCE_MS);
                return; /* too fast, skip */
            }
            key_last_press_time[ev->code] = t;
        }

        fprintf(stderr, "[bridge] SEND KEY: code=%u value=%d t=%u\n", ev->code, ev->value, t);

        /* Send the key event */
        zwp_virtual_keyboard_v1_key(vkeyboard, t, ev->code,
            ev->value ? WL_KEYBOARD_KEY_STATE_PRESSED :
                       WL_KEYBOARD_KEY_STATE_RELEASED);

        /* Update modifier state and send modifiers event */
        uint32_t mod_bit = evdev_to_mod_bit(ev->code);
        if (mod_bit) {
            if (ev->value)
                mod_depressed |= mod_bit;
            else
                mod_depressed &= ~mod_bit;

            zwp_virtual_keyboard_v1_modifiers(vkeyboard,
                mod_depressed, 0, 0, 0);
        }
    }
}

static void sighandler(int sig) {
    (void)sig;
    running = 0;
}

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;

    signal(SIGINT, sighandler);
    signal(SIGTERM, sighandler);
    signal(SIGPIPE, SIG_IGN); /* Don't die on broken pipe, handle gracefully */

    fprintf(stderr, "[bridge] evdev-bridge v3: native Wayland input injection\n");

    /* Connect to Wayland */
    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "[bridge] Cannot connect to Wayland display. Set WAYLAND_DISPLAY.\n");
        return 1;
    }
    fprintf(stderr, "[bridge] Connected to Wayland display\n");

    registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);

    if (!pointer_manager) {
        fprintf(stderr, "[bridge] FATAL: zwlr_virtual_pointer_manager_v1 not available\n");
        return 1;
    }
    if (!keyboard_manager) {
        fprintf(stderr, "[bridge] FATAL: zwp_virtual_keyboard_manager_v1 not available\n");
        return 1;
    }
    if (!seat) {
        fprintf(stderr, "[bridge] FATAL: wl_seat not available\n");
        return 1;
    }

    /* Check version — need v2 for create_virtual_pointer_with_output */
    uint32_t pm_ver = zwlr_virtual_pointer_manager_v1_get_version(pointer_manager);
    fprintf(stderr, "[bridge] Pointer manager bound version: %u\n", pm_ver);

    /* Create virtual pointer */
    if (pm_ver >= 2 && output) {
        vpointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer_with_output(
            pointer_manager, seat, output);
        fprintf(stderr, "[bridge] Created virtual pointer with output\n");
    } else {
        vpointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(
            pointer_manager, seat);
        fprintf(stderr, "[bridge] Created virtual pointer (without output, pm_ver=%u)\n", pm_ver);
    }
    if (!vpointer) {
        fprintf(stderr, "[bridge] Failed to create virtual pointer\n");
        return 1;
    }

    /* Roundtrip to ensure pointer is registered */
    wl_display_roundtrip(display);
    if (check_display_error() < 0) {
        fprintf(stderr, "[bridge] Error after creating virtual pointer\n");
        return 1;
    }

    /* Create virtual keyboard */
    vkeyboard = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(
        keyboard_manager, seat);
    if (!vkeyboard) {
        fprintf(stderr, "[bridge] Failed to create virtual keyboard\n");
        return 1;
    }
    fprintf(stderr, "[bridge] Virtual keyboard created\n");

    /* Roundtrip to ensure keyboard is registered */
    wl_display_roundtrip(display);
    if (check_display_error() < 0) {
        fprintf(stderr, "[bridge] Error after creating virtual keyboard\n");
        return 1;
    }

    /* Upload keymap */
    if (setup_keyboard() < 0) {
        fprintf(stderr, "[bridge] Failed to setup keyboard\n");
        return 1;
    }

    /* Critical: roundtrip after keymap upload so compositor processes the FD */
    wl_display_roundtrip(display);
    if (check_display_error() < 0) {
        fprintf(stderr, "[bridge] Error after keymap upload\n");
        return 1;
    }
    fprintf(stderr, "[bridge] All Wayland objects ready\n");

    /* Wait for Sunshine devices */
    fprintf(stderr, "[bridge] Looking for Sunshine input devices...\n");
    while (running) {
        if (find_device("Keyboard passthrough", kbd_path, sizeof(kbd_path)) == 0 &&
            find_device("Mouse passthrough", rel_mouse_path, sizeof(rel_mouse_path)) == 0) {
            find_device("Mouse passthrough (absolute)", abs_mouse_path, sizeof(abs_mouse_path));
            break;
        }
        fprintf(stderr, "[bridge] Waiting for Sunshine devices...\n");
        sleep(2);
    }

    if (!running) return 0;

    /* Open devices with O_NONBLOCK */
    kbd_fd = open(kbd_path, O_RDONLY | O_NONBLOCK);
    if (kbd_fd < 0) {
        fprintf(stderr, "[bridge] Cannot open keyboard %s: %s\n", kbd_path, strerror(errno));
        return 1;
    }

    rel_mouse_fd = open(rel_mouse_path, O_RDONLY | O_NONBLOCK);
    if (rel_mouse_fd < 0) {
        fprintf(stderr, "[bridge] Cannot open mouse %s: %s\n", rel_mouse_path, strerror(errno));
        return 1;
    }

    if (abs_mouse_path[0]) {
        abs_mouse_fd = open(abs_mouse_path, O_RDONLY | O_NONBLOCK);
        if (abs_mouse_fd < 0) {
            fprintf(stderr, "[bridge] Warning: Cannot open abs mouse %s: %s\n",
                    abs_mouse_path, strerror(errno));
            /* Non-fatal */
        }
    }

    fprintf(stderr, "[bridge] All devices open. Forwarding events...\n");

    /* Get the Wayland display FD for polling */
    int wl_fd = wl_display_get_fd(display);

    /* Main event loop */
    while (running) {
        /* Prepare poll set: wayland fd + evdev fds */
        struct pollfd fds[5];
        int nfds = 0;

        /* Wayland display FD — we need to read compositor responses */
        fds[nfds].fd = wl_fd;
        fds[nfds].events = POLLIN;
        nfds++;

        /* Evdev devices */
        fds[nfds].fd = kbd_fd;
        fds[nfds].events = POLLIN;
        nfds++;

        fds[nfds].fd = rel_mouse_fd;
        fds[nfds].events = POLLIN;
        nfds++;

        if (abs_mouse_fd >= 0) {
            fds[nfds].fd = abs_mouse_fd;
            fds[nfds].events = POLLIN;
            nfds++;
        }

        /* Flush outgoing data before polling */
        while (wl_display_flush(display) == -1) {
            if (errno != EAGAIN) {
                fprintf(stderr, "[bridge] wl_display_flush error: %s\n", strerror(errno));
                running = 0;
                break;
            }
            /* EAGAIN means output buffer full, poll for writable */
            struct pollfd pfd = { .fd = wl_fd, .events = POLLOUT };
            poll(&pfd, 1, -1);
        }
        if (!running) break;

        /* Prepare to read Wayland events */
        while (wl_display_prepare_read(display) != 0) {
            wl_display_dispatch_pending(display);
        }

        int ret = poll(fds, nfds, 100);
        if (ret < 0) {
            wl_display_cancel_read(display);
            if (errno == EINTR) continue;
            fprintf(stderr, "[bridge] poll error: %s\n", strerror(errno));
            break;
        }

        /* Handle Wayland events */
        if (fds[0].revents & POLLIN) {
            wl_display_read_events(display);
        } else {
            wl_display_cancel_read(display);
        }
        wl_display_dispatch_pending(display);

        /* Check for errors */
        if (check_display_error() < 0) {
            running = 0;
            break;
        }

        if (ret == 0) continue; /* timeout */

        /* Check for device disconnection (POLLERR on evdev fds, or POLLHUP without POLLIN) */
        for (int i = 1; i < nfds; i++) {
            if (fds[i].revents & POLLERR) {
                fprintf(stderr, "[bridge] Device fd %d error (revents=0x%x), exiting for restart\n",
                        fds[i].fd, fds[i].revents);
                running = 0;
                break;
            }
            if ((fds[i].revents & POLLHUP) && !(fds[i].revents & POLLIN)) {
                fprintf(stderr, "[bridge] Device fd %d hung up (revents=0x%x), exiting for restart\n",
                        fds[i].fd, fds[i].revents);
                running = 0;
                break;
            }
        }
        if (!running) break;

        /* Read evdev events */
        struct input_event ev;
        int idx = 1; /* start after wayland fd */

        /* Keyboard */
        if (fds[idx].revents & POLLIN) {
            ssize_t n;
            while ((n = read(kbd_fd, &ev, sizeof(ev))) == sizeof(ev)) {
                handle_keyboard_event(&ev);
            }
            if (n < 0 && errno != EAGAIN) {
                fprintf(stderr, "[bridge] Keyboard read error: %s, exiting for restart\n", strerror(errno));
                running = 0; break;
            }
        }
        idx++;

        /* Relative mouse */
        if (fds[idx].revents & POLLIN) {
            ssize_t n;
            while ((n = read(rel_mouse_fd, &ev, sizeof(ev))) == sizeof(ev)) {
                handle_mouse_event(&ev);
            }
            if (n < 0 && errno != EAGAIN) {
                fprintf(stderr, "[bridge] Mouse read error: %s, exiting for restart\n", strerror(errno));
                running = 0; break;
            }
        }
        idx++;

        /* Absolute mouse */
        if (abs_mouse_fd >= 0 && fds[idx].revents & POLLIN) {
            ssize_t n;
            while ((n = read(abs_mouse_fd, &ev, sizeof(ev))) == sizeof(ev)) {
                handle_abs_mouse_event(&ev);
            }
        }

        /* Flush after processing events */
        if (wl_display_flush(display) == -1 && errno != EAGAIN) {
            fprintf(stderr, "[bridge] Final flush error: %s\n", strerror(errno));
            if (check_display_error() < 0) {
                running = 0;
            }
        }
    }

    fprintf(stderr, "[bridge] Shutting down...\n");

    if (kbd_fd >= 0) close(kbd_fd);
    if (rel_mouse_fd >= 0) close(rel_mouse_fd);
    if (abs_mouse_fd >= 0) close(abs_mouse_fd);

    if (vpointer) zwlr_virtual_pointer_v1_destroy(vpointer);
    if (vkeyboard) zwp_virtual_keyboard_v1_destroy(vkeyboard);
    if (pointer_manager) zwlr_virtual_pointer_manager_v1_destroy(pointer_manager);

    wl_display_disconnect(display);
    fprintf(stderr, "[bridge] Clean exit\n");
    return 0;
}
