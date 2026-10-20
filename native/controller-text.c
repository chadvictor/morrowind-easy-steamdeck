/*
 * Morrowind Easy Steam Deck: optional SDL2 input helper (MIT).
 *
 * Inject only into OpenMW, never Steam or a launcher. SDL requires PollEvent
 * on its video/main thread; all helper state is confined to that same thread.
 * No SDL objects, physical keyboard state, engine memory or save files change.
 */
#define _GNU_SOURCE
#include <SDL.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define MES_CONTROLLERS 16
#define MES_PENDING 8
#define MES_QUIT_HOLD_MS 3000u

static int (*next_poll)(SDL_Event *);
static SDL_bool (*text_active)(void);
static Uint32 (*get_ticks)(void);
static SDL_Keymod (*get_mod_state)(void);
static SDL_Window *(*get_keyboard_focus)(void);
static Uint32 (*get_window_id)(SDL_Window *);
static int initialized;
static int enabled;

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
};

static struct controller controllers[MES_CONTROLLERS];
static SDL_Event pending[MES_PENDING];
static unsigned pending_read;
static unsigned pending_count;
static uint32_t random_state;
static unsigned previous_name = UINT32_MAX;

static void resolve_symbols(void)
{
    if (initialized)
        return;
    initialized = 1;
    /* POSIX dlsym permits converting its result to a function pointer. */
    next_poll = (int (*)(SDL_Event *))dlsym(RTLD_NEXT, "SDL_PollEvent");
    text_active = (SDL_bool (*)(void))dlsym(RTLD_NEXT, "SDL_IsTextInputActive");
    get_ticks = (Uint32 (*)(void))dlsym(RTLD_NEXT, "SDL_GetTicks");
    get_mod_state = (SDL_Keymod (*)(void))dlsym(RTLD_NEXT, "SDL_GetModState");
    get_keyboard_focus = (SDL_Window *(*)(void))dlsym(RTLD_NEXT, "SDL_GetKeyboardFocus");
    get_window_id = (Uint32 (*)(SDL_Window *))dlsym(RTLD_NEXT, "SDL_GetWindowID");
    enabled = next_poll && text_active && get_ticks && get_mod_state
        && get_keyboard_focus && get_window_id;
    if (enabled)
        fputs("[MES controller text] ready: View+Y name; View+Menu hold 3s quit\n", stderr);
    else
        fputs("[MES controller text] unavailable: SDL2 symbols missing; input unchanged\n", stderr);
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
    if (controller != NULL)
        memset(controller, 0, sizeof(*controller));
}

static void forget_all(void)
{
    memset(controllers, 0, sizeof(controllers));
}

static void enqueue(const SDL_Event *event)
{
    /* At most one five-event name, or one quit, is staged in one call. */
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

/* Return nonzero only for a Y transition belonging to a handled text combo. */
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
    case SDL_CONTROLLERBUTTONDOWN:
    case SDL_CONTROLLERBUTTONUP:
        break;
    default:
        return 0;
    }
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
            return dequeue(event) ? 1 : result;
        }
        if (handle_event(&incoming)) {
            if (dequeue(event))
                return 1;
        } else {
            *event = incoming;
            return result;
        }
    }
}
