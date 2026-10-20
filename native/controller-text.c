/*
 * Morrowind Easy Steam Deck: optional SDL2 input helper (MIT).
 *
 * Inject only into OpenMW, never Steam or a launcher. SDL requires PollEvent
 * on its video/main thread; input mutation is confined to that same thread.
 * Controller polling getters only read published atomic capture masks.
 * No SDL objects, physical keyboard state, engine memory or save files change.
 */
#define _GNU_SOURCE
#include <SDL.h>
#include <dlfcn.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "keyboard-layout.h"

#define MES_CONTROLLERS 16
#define MES_PENDING 512
#define MES_QUIT_HOLD_MS 3000u
#define MES_STICK_THRESHOLD 12000
#define MES_AXIS_NEUTRAL 6000

static int (*next_poll)(SDL_Event *);
static SDL_bool (*text_active)(void);
static Uint32 (*get_ticks)(void);
static SDL_Keymod (*get_mod_state)(void);
static SDL_Window *(*get_keyboard_focus)(void);
static Uint32 (*get_window_id)(SDL_Window *);
static Sint16 (*next_controller_axis)(SDL_GameController *, SDL_GameControllerAxis);
static Uint8 (*next_controller_button)(SDL_GameController *, SDL_GameControllerButton);
static SDL_Joystick *(*controller_joystick)(SDL_GameController *);
static SDL_JoystickID (*joystick_id)(SDL_Joystick *);
static atomic_int initialized;
static atomic_flag initialization_lock = ATOMIC_FLAG_INIT;
static int enabled;
static int virtual_keyboard_enabled;

struct controller {
    SDL_JoystickID id;
    int used;
    int back;
    int start;
    int y;
    int consume_y;
    int timing;
    int quit_sent;
    Uint32 since;
    Uint32 buttons;
    Uint32 swallowed;
    Uint32 forwarded;
    Uint32 blocked_axes;
    Sint16 axes[SDL_CONTROLLER_AXIS_MAX];
    Sint16 forwarded_axes[SDL_CONTROLLER_AXIS_MAX];
    int back_pending;
    int back_chord;
};

static struct controller controllers[MES_CONTROLLERS];
static SDL_Event pending[MES_PENDING];
static unsigned pending_read;
static unsigned pending_count;
static uint32_t random_state;
static unsigned previous_name = UINT32_MAX;
static int keyboard_open;
static SDL_JoystickID keyboard_owner;
static unsigned keyboard_selection = 15; /* Q in the canonical US layout. */
static int keyboard_shift;
static int keyboard_caps;
static int keyboard_direction;
static Uint32 keyboard_repeat_at;
static Uint32 keyboard_repeat_delay;
static Uint32 keyboard_snapshot_at;
static int keyboard_text_active;
static int swallow_escape;
static SDL_JoystickID removed_ids[MES_CONTROLLERS];
static Uint32 removed_releases[MES_CONTROLLERS];
static unsigned removed_cursor;

/*
 * OpenMW's Lua input getters can run away from the SDL event thread. They only
 * read this atomic publication; the controller state above remains main-thread
 * owned. Device instance IDs are unique while a device is connected.
 */
struct controller_mask {
    atomic_uint_fast64_t buttons;
    atomic_uint_fast64_t axes;
};
static struct controller_mask published[MES_CONTROLLERS];
static atomic_int published_open;

static void keyboard_close(void);
static void publish_masks(void);

static void resolve_symbols(void)
{
    if (atomic_load_explicit(&initialized, memory_order_acquire))
        return;
    while (atomic_flag_test_and_set_explicit(&initialization_lock, memory_order_acquire))
        ;
    if (atomic_load_explicit(&initialized, memory_order_relaxed)) {
        atomic_flag_clear_explicit(&initialization_lock, memory_order_release);
        return;
    }
    /* POSIX dlsym permits converting its result to a function pointer. */
    next_poll = (int (*)(SDL_Event *))dlsym(RTLD_NEXT, "SDL_PollEvent");
    text_active = (SDL_bool (*)(void))dlsym(RTLD_NEXT, "SDL_IsTextInputActive");
    get_ticks = (Uint32 (*)(void))dlsym(RTLD_NEXT, "SDL_GetTicks");
    get_mod_state = (SDL_Keymod (*)(void))dlsym(RTLD_NEXT, "SDL_GetModState");
    get_keyboard_focus = (SDL_Window *(*)(void))dlsym(RTLD_NEXT, "SDL_GetKeyboardFocus");
    get_window_id = (Uint32 (*)(SDL_Window *))dlsym(RTLD_NEXT, "SDL_GetWindowID");
    next_controller_axis = (Sint16 (*)(SDL_GameController *, SDL_GameControllerAxis))
        dlsym(RTLD_NEXT, "SDL_GameControllerGetAxis");
    next_controller_button = (Uint8 (*)(SDL_GameController *, SDL_GameControllerButton))
        dlsym(RTLD_NEXT, "SDL_GameControllerGetButton");
    controller_joystick = (SDL_Joystick *(*)(SDL_GameController *))
        dlsym(RTLD_NEXT, "SDL_GameControllerGetJoystick");
    joystick_id = (SDL_JoystickID (*)(SDL_Joystick *))dlsym(RTLD_NEXT, "SDL_JoystickInstanceID");
    enabled = next_poll && text_active && get_ticks && get_mod_state
        && get_keyboard_focus && get_window_id;
    virtual_keyboard_enabled = getenv("MES_VIRTUAL_KEYBOARD") != NULL
        && strcmp(getenv("MES_VIRTUAL_KEYBOARD"), "1") == 0
        && next_controller_axis && next_controller_button && controller_joystick && joystick_id;
    if (enabled) {
        fputs(virtual_keyboard_enabled
            ? "[MES controller text] ready: View+X keyboard; View+Y name; View+Menu hold 3s quit\n"
            : "[MES controller text] ready: View+Y name; View+Menu hold 3s quit\n", stderr);
    } else
        fputs("[MES controller text] unavailable: SDL2 symbols missing; input unchanged\n", stderr);
    atomic_store_explicit(&initialized, 1, memory_order_release);
    atomic_flag_clear_explicit(&initialization_lock, memory_order_release);
}

static struct controller *find_controller(SDL_JoystickID id, int create)
{
    struct controller *empty = NULL;
    unsigned i;
    for (i = 0; i < MES_CONTROLLERS; ++i) {
        if (controllers[i].used && controllers[i].id == id)
            return &controllers[i];
        if (!controllers[i].used && empty == NULL)
            empty = &controllers[i];
    }
    /* A full table fails open: unrelated controller input still passes. */
    if (create && empty != NULL) {
        memset(empty, 0, sizeof(*empty));
        empty->used = 1;
        empty->id = id;
        return empty;
    }
    return NULL;
}

static void forget_controller(SDL_JoystickID id)
{
    struct controller *controller = find_controller(id, 0);
    if (keyboard_open && keyboard_owner == id)
        keyboard_close();
    if (controller != NULL) {
        if (virtual_keyboard_enabled) {
            removed_ids[removed_cursor] = id;
            removed_releases[removed_cursor] = controller->swallowed | controller->buttons;
            removed_cursor = (removed_cursor + 1) % MES_CONTROLLERS;
        }
        memset(controller, 0, sizeof(*controller));
    }
}

static void forget_all(void)
{
    unsigned i;
    if (!virtual_keyboard_enabled) {
        memset(controllers, 0, sizeof(controllers));
        return;
    }
    keyboard_close();
    for (i = 0; i < MES_CONTROLLERS; ++i) {
        struct controller *controller = &controllers[i];
        SDL_JoystickID id = controller->id;
        Uint32 swallowed = controller->swallowed | controller->buttons;
        int used = controller->used;
        memset(controller, 0, sizeof(*controller));
        controller->id = id;
        controller->used = used;
        /* A late release after focus loss must not activate a native modal. */
        controller->swallowed = swallowed;
    }
}

static void enqueue(const SDL_Event *event)
{
    /* An open can neutralize all 16 tracked controllers in one bounded batch. */
    if (pending_count < MES_PENDING) {
        pending[(pending_read + pending_count) % MES_PENDING] = *event;
        ++pending_count;
    }
}

static int dequeue(SDL_Event *event)
{
    if (pending_count == 0)
        return 0;
    *event = pending[pending_read];
    pending_read = (pending_read + 1) % MES_PENDING;
    --pending_count;
    return 1;
}

static uint32_t next_random(void)
{
    if (random_state == 0)
        random_state = get_ticks() ^ (uint32_t)(uintptr_t)&random_state
            ^ ((uint32_t)getpid() * UINT32_C(2654435761)) ^ UINT32_C(0x9e3779b9);
    if (random_state == 0)
        random_state = 1;
    random_state ^= random_state << 13;
    random_state ^= random_state >> 17;
    random_state ^= random_state << 5;
    return random_state;
}

static void make_name(char *destination, size_t size)
{
    static const char *const first[] = {
        "Nara", "Dalen", "Veya", "Ralen", "Arin", "Sera", "Varen", "Taren",
        "Runa", "Fara", "Eran", "Neri", "Ilen", "Mira", "Tala", "Soren"
    };
    static const char *const last[] = {
        "Veloren", "Dresan", "Oravel", "Serethi", "Varon", "Nerano", "Relas", "Moren",
        "Aravel", "Valen", "Terano", "Sarano", "Veleth", "Rethan", "Doran", "Ravani"
    };
    unsigned choice = next_random() % 256u;
    if (choice == previous_name)
        choice = (choice + 1u) % 256u;
    previous_name = choice;
    /* ASCII also remains valid UTF-8. All generated names fit SDL's 32 bytes. */
    (void)snprintf(destination, size, "%s %s", first[choice / 16u], last[choice % 16u]);
}

static void enqueue_key(Uint32 type, SDL_Keycode key, SDL_Scancode scan,
    SDL_Keymod modifiers, Uint32 ticks, Uint32 window)
{
    SDL_Event event;
    memset(&event, 0, sizeof(event));
    event.type = type;
    event.key.timestamp = ticks;
    event.key.windowID = window;
    event.key.state = type == SDL_KEYDOWN ? SDL_PRESSED : SDL_RELEASED;
    event.key.keysym.sym = key;
    event.key.keysym.scancode = scan;
    event.key.keysym.mod = (Uint16)modifiers;
    enqueue(&event);
}

static void enqueue_name(void)
{
    SDL_Event event;
    SDL_Window *focus = get_keyboard_focus();
    Uint32 window = focus == NULL ? 0 : get_window_id(focus);
    Uint32 ticks = get_ticks();
    SDL_Keymod modifiers = get_mod_state();
    int synthesize_control = (modifiers & KMOD_CTRL) == 0;
    SDL_Keymod selection_modifiers = synthesize_control
        ? (SDL_Keymod)(modifiers | KMOD_LCTRL) : modifiers;

    /*
     * A private queue guarantees ordering, even when SDL's event filter rejects
     * pushed events. Do not call SDL_SetModState or change SDL's physical keys.
     * If Ctrl is already physically held, do not release it synthetically.
     */
    if (synthesize_control)
        enqueue_key(SDL_KEYDOWN, SDLK_LCTRL, SDL_SCANCODE_LCTRL,
            selection_modifiers, ticks, window);
    enqueue_key(SDL_KEYDOWN, SDLK_a, SDL_SCANCODE_A, selection_modifiers, ticks, window);
    enqueue_key(SDL_KEYUP, SDLK_a, SDL_SCANCODE_A, selection_modifiers, ticks, window);
    if (synthesize_control)
        enqueue_key(SDL_KEYUP, SDLK_LCTRL, SDL_SCANCODE_LCTRL, modifiers, ticks, window);
    memset(&event, 0, sizeof(event));
    event.type = SDL_TEXTINPUT;
    event.text.timestamp = ticks;
    event.text.windowID = window;
    make_name(event.text.text, sizeof(event.text.text));
    enqueue(&event);
}

static Uint32 input_window(void)
{
    SDL_Window *focus = get_keyboard_focus();
    return focus == NULL ? 0 : get_window_id(focus);
}

static Uint32 button_bit(Uint8 button)
{
    return button < SDL_CONTROLLER_BUTTON_MAX && button < 32 ? UINT32_C(1) << button : 0;
}

static void keyboard_snapshot(void)
{
    SDL_Keymod modifiers = KMOD_LGUI;
    SDL_Scancode code = (SDL_Scancode)(keyboard_open ? 400 + keyboard_selection : 499);
    keyboard_text_active = text_active() == SDL_TRUE;
    if (keyboard_shift)
        modifiers = (SDL_Keymod)(modifiers | KMOD_LSHIFT);
    if (keyboard_caps)
        modifiers = (SDL_Keymod)(modifiers | KMOD_LCTRL);
    if (keyboard_text_active)
        modifiers = (SDL_Keymod)(modifiers | KMOD_LALT);
    keyboard_snapshot_at = get_ticks();
    /*
     * KEYUP cannot become a new binding in OpenMW's key-detection screen.
     * The reserved (<512) scancode survives into MENU onKeyRelease.code.
     * Its masked keycode maps to MyGUI::None and cannot enter field text.
     */
    enqueue_key(SDL_KEYUP, SDL_SCANCODE_TO_KEYCODE(code), code, modifiers,
        keyboard_snapshot_at, input_window());
}

static void keyboard_close(void)
{
    unsigned i;
    if (!keyboard_open)
        return;
    keyboard_open = 0;
    keyboard_shift = 0;
    keyboard_direction = 0;
    for (i = 0; i < MES_CONTROLLERS; ++i)
        controllers[i].swallowed |= controllers[i].buttons;
    publish_masks();
    atomic_store_explicit(&published_open, 0, memory_order_release);
    keyboard_snapshot();
}

static void neutralize_controls(void)
{
    unsigned i;
    for (i = 0; i < MES_CONTROLLERS; ++i) {
        struct controller *controller = &controllers[i];
        unsigned value;
        if (!controller->used)
            continue;
        controller->swallowed |= controller->buttons;
        for (value = 0; value < 32; ++value) {
            if ((controller->forwarded & (UINT32_C(1) << value)) != 0) {
                SDL_Event event;
                memset(&event, 0, sizeof(event));
                event.type = SDL_CONTROLLERBUTTONUP;
                event.cbutton.timestamp = get_ticks();
                event.cbutton.which = controller->id;
                event.cbutton.button = (Uint8)value;
                event.cbutton.state = SDL_RELEASED;
                enqueue(&event);
            }
        }
        controller->forwarded = 0;
        for (value = 0; value < SDL_CONTROLLER_AXIS_MAX; ++value) {
            if (controller->forwarded_axes[value] != 0) {
                SDL_Event event;
                memset(&event, 0, sizeof(event));
                event.type = SDL_CONTROLLERAXISMOTION;
                event.caxis.timestamp = get_ticks();
                event.caxis.which = controller->id;
                event.caxis.axis = (Uint8)value;
                enqueue(&event);
                controller->forwarded_axes[value] = 0;
                controller->blocked_axes |= UINT32_C(1) << value;
            }
        }
    }
}

static void keyboard_show(SDL_JoystickID owner)
{
    atomic_store_explicit(&published_open, 1, memory_order_release);
    keyboard_owner = owner;
    keyboard_open = 1;
    keyboard_shift = 0;
    keyboard_direction = 0;
    neutralize_controls();
    keyboard_snapshot();
}

/* Directions are left=-1, right=1, up=-2, down=2. */
static void keyboard_move(int direction)
{
    const struct mes_keyboard_key *current = &mes_keyboard_keys[keyboard_selection];
    unsigned i, first = keyboard_selection, last = keyboard_selection, best = keyboard_selection;
    int row = current->row;
    float center = current->x + current->width / 2.f;
    float distance = 1000.f;
    if (direction == -1 || direction == 1) {
        for (i = 0; i < MES_KEYBOARD_KEY_COUNT; ++i) {
            if (mes_keyboard_keys[i].row == row) {
                if (i < first)
                    first = i;
                if (i > last)
                    last = i;
            }
        }
        keyboard_selection = direction < 0
            ? (keyboard_selection == first ? last : keyboard_selection - 1)
            : (keyboard_selection == last ? first : keyboard_selection + 1);
    } else {
        int target_row = row + (direction < 0 ? -1 : 1);
        if (target_row < 0 || target_row >= MES_KEYBOARD_ROWS)
            return;
        for (i = 0; i < MES_KEYBOARD_KEY_COUNT; ++i) {
            const struct mes_keyboard_key *key = &mes_keyboard_keys[i];
            float difference = key->x + key->width / 2.f - center;
            if (difference < 0)
                difference = -difference;
            if (key->row == target_row && difference < distance) {
                best = i;
                distance = difference;
            }
        }
        keyboard_selection = best;
    }
    keyboard_snapshot();
}

static int navigation_direction(const struct controller *controller)
{
    int horizontal = ((controller->buttons & button_bit(SDL_CONTROLLER_BUTTON_DPAD_RIGHT)) != 0)
        - ((controller->buttons & button_bit(SDL_CONTROLLER_BUTTON_DPAD_LEFT)) != 0);
    int vertical = ((controller->buttons & button_bit(SDL_CONTROLLER_BUTTON_DPAD_DOWN)) != 0)
        - ((controller->buttons & button_bit(SDL_CONTROLLER_BUTTON_DPAD_UP)) != 0);
    int x = controller->axes[SDL_CONTROLLER_AXIS_LEFTX];
    int y = controller->axes[SDL_CONTROLLER_AXIS_LEFTY];
    if (horizontal != 0 || vertical != 0)
        return horizontal != 0 ? horizontal : vertical * 2;
    if (abs(x) < MES_STICK_THRESHOLD && abs(y) < MES_STICK_THRESHOLD)
        return 0;
    return abs(x) >= abs(y) ? (x < 0 ? -1 : 1) : (y < 0 ? -2 : 2);
}

static void keyboard_navigation(void)
{
    struct controller *controller = find_controller(keyboard_owner, 0);
    int direction = controller == NULL ? 0 : navigation_direction(controller);
    Uint32 now = get_ticks();
    if (direction != keyboard_direction) {
        keyboard_direction = direction;
        keyboard_repeat_at = now;
        keyboard_repeat_delay = 350;
        if (direction != 0)
            keyboard_move(direction);
    } else if (direction != 0 && (Uint32)(now - keyboard_repeat_at) >= keyboard_repeat_delay) {
        keyboard_move(direction);
        keyboard_repeat_at = now;
        keyboard_repeat_delay = 90;
    }
}

static void keyboard_edit(SDL_Keycode key, SDL_Scancode code)
{
    Uint32 now;
    Uint32 window;
    if (!text_active())
        return;
    now = get_ticks();
    window = input_window();
    enqueue_key(SDL_KEYDOWN, key, code, get_mod_state(), now, window);
    enqueue_key(SDL_KEYUP, key, code, get_mod_state(), now, window);
}

static void keyboard_type(const char *text)
{
    SDL_Event event;
    if (!text_active())
        return;
    memset(&event, 0, sizeof(event));
    event.type = SDL_TEXTINPUT;
    event.text.timestamp = get_ticks();
    event.text.windowID = input_window();
    (void)snprintf(event.text.text, sizeof(event.text.text), "%s", text);
    enqueue(&event);
    if (keyboard_shift) {
        keyboard_shift = 0;
        keyboard_snapshot();
    }
}

static void keyboard_activate(void)
{
    const struct mes_keyboard_key *key = &mes_keyboard_keys[keyboard_selection];
    switch (key->action) {
    case MES_KEY_TEXT: {
        int letter = key->label[0] >= 'a' && key->label[0] <= 'z' && key->label[1] == '\0';
        int shifted = letter ? keyboard_shift != keyboard_caps : keyboard_shift;
        keyboard_type(shifted ? key->shifted : key->label);
        break;
    }
    case MES_KEY_SPACE: keyboard_type(" "); break;
    case MES_KEY_SHIFT: keyboard_shift = !keyboard_shift; keyboard_snapshot(); break;
    case MES_KEY_CAPS: keyboard_caps = !keyboard_caps; keyboard_snapshot(); break;
    case MES_KEY_BACKSPACE: keyboard_edit(SDLK_BACKSPACE, SDL_SCANCODE_BACKSPACE); break;
    case MES_KEY_TAB: keyboard_edit(SDLK_TAB, SDL_SCANCODE_TAB); break;
    case MES_KEY_LEFT: keyboard_edit(SDLK_LEFT, SDL_SCANCODE_LEFT); break;
    case MES_KEY_RIGHT: keyboard_edit(SDLK_RIGHT, SDL_SCANCODE_RIGHT); break;
    case MES_KEY_HOME: keyboard_edit(SDLK_HOME, SDL_SCANCODE_HOME); break;
    case MES_KEY_END: keyboard_edit(SDLK_END, SDL_SCANCODE_END); break;
    case MES_KEY_DELETE: keyboard_edit(SDLK_DELETE, SDL_SCANCODE_DELETE); break;
    case MES_KEY_ENTER:
        if (text_active()) {
            keyboard_edit(SDLK_RETURN, SDL_SCANCODE_RETURN);
            keyboard_close();
        }
        break;
    case MES_KEY_CLOSE: keyboard_close(); break;
    }
}

static void update_hold(struct controller *controller)
{
    if (controller->back && controller->start) {
        if (!controller->timing) {
            controller->timing = 1;
            controller->since = get_ticks();
        }
    } else {
        controller->timing = 0;
        controller->quit_sent = 0;
    }
}

static int keyboard_button(const SDL_Event *event)
{
    int down = event->type == SDL_CONTROLLERBUTTONDOWN;
    Uint8 button = event->cbutton.button;
    Uint32 bit = button_bit(button);
    struct controller *controller = find_controller(event->cbutton.which, down);
    int was_down;
    if (controller == NULL) {
        unsigned i;
        if (!down)
            for (i = 0; i < MES_CONTROLLERS; ++i)
                if (removed_ids[i] == event->cbutton.which && (removed_releases[i] & bit) != 0) {
                    removed_releases[i] &= ~bit;
                    return 1;
                }
        return keyboard_open;
    }
    was_down = (controller->buttons & bit) != 0;
    if (down) {
        if (!was_down)
            controller->swallowed &= ~bit; /* Recover from a lost release on focus loss. */
        controller->buttons |= bit;
    } else
        controller->buttons &= ~bit;
    controller->back = (controller->buttons & button_bit(SDL_CONTROLLER_BUTTON_BACK)) != 0;
    controller->start = (controller->buttons & button_bit(SDL_CONTROLLER_BUTTON_START)) != 0;
    update_hold(controller);
    if (!keyboard_open && down && was_down && (controller->swallowed & bit) != 0)
        return 1;

    if (button == SDL_CONTROLLER_BUTTON_BACK) {
        if (down && !was_down) {
            controller->back_pending = 1;
            controller->back_chord = keyboard_open || controller->start;
        } else if (!down) {
            if (controller->back_pending && !controller->back_chord && !keyboard_open) {
                SDL_Event tap = *event;
                tap.type = SDL_CONTROLLERBUTTONDOWN;
                tap.cbutton.state = SDL_PRESSED;
                enqueue(&tap);
                enqueue(event);
            }
            controller->back_pending = 0;
            controller->swallowed &= ~bit;
        }
        return 1;
    }
    if (!down && (controller->swallowed & bit) != 0) {
        controller->swallowed &= ~bit;
        if (button == SDL_CONTROLLER_BUTTON_Y)
            controller->consume_y = 0;
        if (keyboard_open && controller->id == keyboard_owner)
            keyboard_navigation();
        return 1;
    }
    if (button == SDL_CONTROLLER_BUTTON_START && controller->back) {
        controller->back_chord = 1;
        if (down)
            controller->swallowed |= bit;
        return 1;
    }
    if (keyboard_open) {
        if (down)
            controller->swallowed |= bit;
        if (controller->id != keyboard_owner)
            return 1;
        if (down && !was_down) {
            switch (button) {
            case SDL_CONTROLLER_BUTTON_A: keyboard_activate(); break;
            case SDL_CONTROLLER_BUTTON_B:
            case SDL_CONTROLLER_BUTTON_START: keyboard_close(); break;
            case SDL_CONTROLLER_BUTTON_X:
                if (controller->back) {
                    controller->back_chord = 1;
                    keyboard_close();
                } else
                    keyboard_edit(SDLK_BACKSPACE, SDL_SCANCODE_BACKSPACE);
                break;
            case SDL_CONTROLLER_BUTTON_Y:
                keyboard_shift = !keyboard_shift;
                keyboard_snapshot();
                break;
            case SDL_CONTROLLER_BUTTON_LEFTSHOULDER: keyboard_edit(SDLK_LEFT, SDL_SCANCODE_LEFT); break;
            case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: keyboard_edit(SDLK_RIGHT, SDL_SCANCODE_RIGHT); break;
            default: break;
            }
        }
        if (keyboard_open)
            keyboard_navigation();
        return 1;
    }
    if (down && !was_down && controller->back && button == SDL_CONTROLLER_BUTTON_X) {
        controller->back_chord = 1;
        controller->swallowed |= bit;
        keyboard_show(controller->id);
        return 1;
    }
    if (button == SDL_CONTROLLER_BUTTON_Y) {
        if (controller->consume_y) {
            if (!down)
                controller->consume_y = 0;
            return 1;
        }
        if (down && !was_down && controller->back && text_active()) {
            controller->back_chord = 1;
            controller->consume_y = 1;
            controller->swallowed |= bit;
            enqueue_name();
            return 1;
        }
    }
    if (down)
        controller->forwarded |= bit;
    else
        controller->forwarded &= ~bit;
    return 0;
}

static int keyboard_axis(const SDL_Event *event)
{
    Uint8 axis = event->caxis.axis;
    struct controller *controller = find_controller(event->caxis.which, 1);
    Uint32 bit;
    if (controller == NULL || axis >= SDL_CONTROLLER_AXIS_MAX)
        return keyboard_open;
    bit = UINT32_C(1) << axis;
    controller->axes[axis] = event->caxis.value;
    if (keyboard_open) {
        if (abs((int)event->caxis.value) > MES_AXIS_NEUTRAL)
            controller->blocked_axes |= bit;
        else
            controller->blocked_axes &= ~bit;
        if (controller->id == keyboard_owner)
            keyboard_navigation();
        return 1;
    }
    if ((controller->blocked_axes & bit) != 0) {
        if (abs((int)event->caxis.value) <= MES_AXIS_NEUTRAL) {
            SDL_Event neutral = *event;
            neutral.caxis.value = 0;
            controller->blocked_axes &= ~bit;
            enqueue(&neutral);
        }
        return 1;
    }
    controller->forwarded_axes[axis] = event->caxis.value;
    return 0;
}

static void keyboard_idle(void)
{
    if (!keyboard_open)
        return;
    keyboard_navigation();
    if (keyboard_text_active != (text_active() == SDL_TRUE)
        || (Uint32)(get_ticks() - keyboard_snapshot_at) >= 1000)
        keyboard_snapshot();
}

static void enqueue_due_quit(void)
{
    unsigned i;
    Uint32 now = get_ticks();
    for (i = 0; i < MES_CONTROLLERS; ++i) {
        struct controller *controller = &controllers[i];
        if (controller->used && controller->timing && !controller->quit_sent
            && (Uint32)(now - controller->since) >= MES_QUIT_HOLD_MS) {
            SDL_Event event;
            unsigned j;
            keyboard_close();
            memset(&event, 0, sizeof(event));
            event.type = SDL_QUIT;
            event.quit.timestamp = now;
            enqueue(&event);
            /* Simultaneous holds on several devices still produce one quit. */
            for (j = 0; j < MES_CONTROLLERS; ++j)
                if (controllers[j].timing)
                    controllers[j].quit_sent = 1;
            return;
        }
    }
}

/* Return nonzero for input deliberately captured by an enabled helper action. */
static int handle_event(const SDL_Event *event)
{
    struct controller *controller;
    int down;
    int was_y;
    switch (event->type) {
    case SDL_QUIT:
    case SDL_APP_TERMINATING:
    case SDL_APP_WILLENTERBACKGROUND:
    case SDL_APP_DIDENTERBACKGROUND:
        forget_all();
        return 0;
    case SDL_WINDOWEVENT:
        if (event->window.event == SDL_WINDOWEVENT_FOCUS_LOST
            || event->window.event == SDL_WINDOWEVENT_HIDDEN
            || event->window.event == SDL_WINDOWEVENT_MINIMIZED
            || event->window.event == SDL_WINDOWEVENT_CLOSE)
            forget_all();
        return 0;
    case SDL_CONTROLLERDEVICEREMOVED:
    case SDL_CONTROLLERDEVICEREMAPPED:
        forget_controller(event->cdevice.which);
        return 0;
    case SDL_JOYDEVICEREMOVED:
        forget_controller(event->jdevice.which);
        return 0;
    case SDL_KEYDOWN:
    case SDL_KEYUP:
        if (virtual_keyboard_enabled && event->key.keysym.sym == SDLK_ESCAPE) {
            if (event->type == SDL_KEYDOWN && keyboard_open) {
                swallow_escape = 1;
                keyboard_close();
            }
            if (swallow_escape) {
                if (event->type == SDL_KEYUP)
                    swallow_escape = 0;
                return 1;
            }
        }
        return 0;
    case SDL_CONTROLLERAXISMOTION:
        return virtual_keyboard_enabled ? keyboard_axis(event) : 0;
    case SDL_CONTROLLERBUTTONDOWN:
    case SDL_CONTROLLERBUTTONUP:
        break;
    default:
        return 0;
    }
    if (virtual_keyboard_enabled)
        return keyboard_button(event);
    if (event->cbutton.button != SDL_CONTROLLER_BUTTON_BACK
        && event->cbutton.button != SDL_CONTROLLER_BUTTON_START
        && event->cbutton.button != SDL_CONTROLLER_BUTTON_Y)
        return 0;
    down = event->type == SDL_CONTROLLERBUTTONDOWN;
    controller = find_controller(event->cbutton.which, down);
    if (controller == NULL)
        return 0;
    if (event->cbutton.button == SDL_CONTROLLER_BUTTON_BACK)
        controller->back = down;
    if (event->cbutton.button == SDL_CONTROLLER_BUTTON_START)
        controller->start = down;
    if (controller->back && controller->start) {
        if (!controller->timing) {
            controller->timing = 1;
            controller->since = get_ticks();
        }
    } else {
        controller->timing = 0;
        controller->quit_sent = 0;
    }
    if (event->cbutton.button != SDL_CONTROLLER_BUTTON_Y)
        return 0;
    was_y = controller->y;
    controller->y = down;
    if (controller->consume_y) {
        if (!down)
            controller->consume_y = 0;
        return 1;
    }
    if (down && !was_y && controller->back && text_active()) {
        controller->consume_y = 1;
        enqueue_name();
        return 1;
    }
    return 0;
}

static void publish_masks(void)
{
    unsigned i;
    for (i = 0; i < MES_CONTROLLERS; ++i) {
        const struct controller *controller = &controllers[i];
        Uint32 buttons = controller->swallowed;
        uint_fast64_t identity = (uint_fast64_t)(Uint32)controller->id << 32;
        if (controller->back_pending)
            buttons |= button_bit(SDL_CONTROLLER_BUTTON_BACK);
        /*
         * Pack instance ID and mask in one atomic word, so a racing reader
         * cannot associate an old mask with a newly connected device.
         */
        atomic_store_explicit(&published[i].buttons,
            controller->used ? identity | buttons : 0, memory_order_release);
        atomic_store_explicit(&published[i].axes,
            controller->used ? identity | controller->blocked_axes : 0, memory_order_release);
    }
}

static int controller_is_masked(SDL_GameController *gamecontroller, unsigned value, int axis)
{
    SDL_Joystick *joystick;
    SDL_JoystickID id;
    unsigned i;
    if (!enabled || !virtual_keyboard_enabled || value >= 32)
        return 0;
    if (atomic_load_explicit(&published_open, memory_order_acquire))
        return 1;
    joystick = controller_joystick(gamecontroller);
    if (joystick == NULL)
        return 0;
    id = joystick_id(joystick);
    for (i = 0; i < MES_CONTROLLERS; ++i) {
        uint_fast64_t packet = axis
            ? atomic_load_explicit(&published[i].axes, memory_order_acquire)
            : atomic_load_explicit(&published[i].buttons, memory_order_acquire);
        if ((Uint32)(packet >> 32) != (Uint32)id)
            continue;
        if (((Uint32)packet & (UINT32_C(1) << value)) != 0)
            return 1;
    }
    return 0;
}

__attribute__((visibility("default"))) Sint16 SDLCALL SDL_GameControllerGetAxis(
    SDL_GameController *gamecontroller, SDL_GameControllerAxis axis)
{
    resolve_symbols();
    if (next_controller_axis == NULL)
        return 0;
    return controller_is_masked(gamecontroller, (unsigned)axis, 1)
        ? 0 : next_controller_axis(gamecontroller, axis);
}

__attribute__((visibility("default"))) Uint8 SDLCALL SDL_GameControllerGetButton(
    SDL_GameController *gamecontroller, SDL_GameControllerButton button)
{
    resolve_symbols();
    if (next_controller_button == NULL)
        return 0;
    return controller_is_masked(gamecontroller, (unsigned)button, 0)
        ? 0 : next_controller_button(gamecontroller, button);
}

__attribute__((visibility("default"))) int SDLCALL SDL_PollEvent(SDL_Event *event)
{
    SDL_Event incoming;
    int result;
    resolve_symbols();
    if (next_poll == NULL)
        return 0;
    if (!enabled)
        return next_poll(event);
    /*
     * NULL is SDL's non-consuming peek. It must not advance our input state or
     * clock, consume a device event, or remove a pending synthetic event.
     */
    if (event == NULL)
        return pending_count != 0 ? 1 : next_poll(NULL);
    if (dequeue(event))
        return 1;
    for (;;) {
        result = next_poll(&incoming);
        if (result <= 0) {
            /*
             * SDL's poll sentinel can return 0 before a queued button release.
             * Give real input the next cycle before testing the held state.
             * OpenMW polls idle frames too, so no new event is needed to quit.
             */
            if (next_poll(NULL) > 0)
                return result;
            enqueue_due_quit();
            if (virtual_keyboard_enabled)
                keyboard_idle();
            return dequeue(event) ? 1 : result;
        }
        result = handle_event(&incoming);
        if (virtual_keyboard_enabled)
            publish_masks();
        if (result) {
            if (dequeue(event))
                return 1;
        } else {
            *event = incoming;
            return 1;
        }
    }
}
