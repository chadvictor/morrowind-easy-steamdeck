/*
 * Linux SDL2 integration tests. No OpenMW, controller or display is required.
 * The optional clock shim is TEST ONLY and is never part of the shipped helper.
 */
#define _GNU_SOURCE
#include <SDL.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef MES_TEST_CLOCK

Uint32 SDLCALL SDL_GetTicks(void)
{
    static Uint32 (*real_ticks)(void);
    const char *value = getenv("MES_TEST_TICKS");
    if (value != NULL)
        return (Uint32)strtoul(value, NULL, 10);
    if (real_ticks == NULL)
        real_ticks = (Uint32 (*)(void))dlsym(RTLD_NEXT, "SDL_GetTicks");
    return real_ticks == NULL ? 0 : real_ticks();
}

#else

static unsigned tests;
#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "FAIL line %d: %s (SDL: %s)\n", __LINE__, #condition, SDL_GetError()); \
        exit(1); \
    } \
} while (0)

static void passed(const char *description)
{
    printf("ok %u - %s\n", ++tests, description);
}

static void ticks(Uint32 value)
{
    char buffer[32];
    (void)snprintf(buffer, sizeof(buffer), "%u", (unsigned)value);
    CHECK(setenv("MES_TEST_TICKS", buffer, 1) == 0);
    CHECK(SDL_GetTicks() == value);
}

static void push(SDL_Event *event)
{
    CHECK(SDL_PushEvent(event) == 1);
}

static SDL_Event next(void)
{
    SDL_Event event;
    unsigned attempts;
    /*
     * SDL2's poll sentinel may finish the previous event cycle before reaching
     * a newly pushed event. A second poll begins the next cycle without sleep.
     */
    for (attempts = 0; attempts < 4; ++attempts)
        if (SDL_PollEvent(&event) == 1)
            return event;
    fprintf(stderr, "FAIL: expected an event, received none\n");
    exit(1);
}

static void empty(void)
{
    SDL_Event event;
    unsigned attempts;
    for (attempts = 0; attempts < 3; ++attempts) {
        int result = SDL_PollEvent(&event);
        if (result != 0)
            fprintf(stderr, "Unexpected event type: 0x%x\n", (unsigned)event.type);
        CHECK(result == 0);
    }
}

static void button(SDL_JoystickID id, Uint8 value, int down)
{
    SDL_Event event;
    memset(&event, 0, sizeof(event));
    event.type = down ? SDL_CONTROLLERBUTTONDOWN : SDL_CONTROLLERBUTTONUP;
    event.cbutton.which = id;
    event.cbutton.button = value;
    event.cbutton.state = down ? SDL_PRESSED : SDL_RELEASED;
    push(&event);
}

static void expect_button(SDL_JoystickID id, Uint8 value, int down)
{
    SDL_Event event = next();
    CHECK(event.type == (Uint32)(down ? SDL_CONTROLLERBUTTONDOWN : SDL_CONTROLLERBUTTONUP));
    CHECK(event.cbutton.which == id);
    CHECK(event.cbutton.button == value);
    CHECK(event.cbutton.state == (down ? SDL_PRESSED : SDL_RELEASED));
}

static void pass_button(SDL_JoystickID id, Uint8 value, int down)
{
    button(id, value, down);
    expect_button(id, value, down);
}

static void keyboard(Uint32 type, SDL_Keycode key, SDL_Scancode scan, SDL_Keymod mod)
{
    SDL_Event event;
    memset(&event, 0, sizeof(event));
    event.type = type;
    event.key.windowID = 987;
    event.key.state = type == SDL_KEYDOWN ? SDL_PRESSED : SDL_RELEASED;
    event.key.keysym.sym = key;
    event.key.keysym.scancode = scan;
    event.key.keysym.mod = (Uint16)mod;
    push(&event);
}

static void expect_key(Uint32 type, SDL_Keycode key, SDL_Scancode scan)
{
    SDL_Event event = next();
    CHECK(event.type == type);
    CHECK(event.key.keysym.sym == key);
    CHECK(event.key.keysym.scancode == scan);
    CHECK(event.key.repeat == 0);
    CHECK(event.key.state == (type == SDL_KEYDOWN ? SDL_PRESSED : SDL_RELEASED));
    if (key == SDLK_a)
        CHECK((event.key.keysym.mod & KMOD_CTRL) != 0);
}

static void read_name(char *destination, int physical_ctrl)
{
    SDL_Event event;
    size_t i;
    if (!physical_ctrl)
        expect_key(SDL_KEYDOWN, SDLK_LCTRL, SDL_SCANCODE_LCTRL);
    expect_key(SDL_KEYDOWN, SDLK_a, SDL_SCANCODE_A);
    /* Peek twice at an event already staged in the private queue. */
    CHECK(SDL_PollEvent(NULL) == 1);
    CHECK(SDL_PollEvent(NULL) == 1);
    expect_key(SDL_KEYUP, SDLK_a, SDL_SCANCODE_A);
    if (!physical_ctrl)
        expect_key(SDL_KEYUP, SDLK_LCTRL, SDL_SCANCODE_LCTRL);
    event = next();
    CHECK(event.type == SDL_TEXTINPUT);
    CHECK(memchr(event.text.text, '\0', sizeof(event.text.text)) != NULL);
    CHECK(strlen(event.text.text) >= 5 && strlen(event.text.text) < 32);
    CHECK(strchr(event.text.text, ' ') != NULL);
    for (i = 0; event.text.text[i] != '\0'; ++i)
        CHECK(event.text.text[i] == ' '
            || (event.text.text[i] >= 'A' && event.text.text[i] <= 'Z')
            || (event.text.text[i] >= 'a' && event.text.text[i] <= 'z'));
    if (destination != NULL)
        memcpy(destination, event.text.text, sizeof(event.text.text));
}

static void reset(int enable_text)
{
    SDL_Event event;
    unsigned attempts;
    unsigned zeros = 0;
    SDL_StopTextInput();
    SDL_SetModState(KMOD_NONE);
    memset(&event, 0, sizeof(event));
    event.type = SDL_WINDOWEVENT;
    event.window.event = SDL_WINDOWEVENT_FOCUS_LOST;
    push(&event);
    for (attempts = 0; attempts < 256 && zeros < 3; ++attempts) {
        if (SDL_PollEvent(&event) == 0)
            ++zeros;
        else
            zeros = 0;
    }
    CHECK(zeros == 3);
    SDL_FlushEvents(SDL_FIRSTEVENT, SDL_LASTEVENT);
    ticks(1000);
    if (enable_text)
        SDL_StartTextInput();
    CHECK(SDL_IsTextInputActive() == (enable_text ? SDL_TRUE : SDL_FALSE));
}

static void hold(SDL_JoystickID id)
{
    pass_button(id, SDL_CONTROLLER_BUTTON_BACK, 1);
    pass_button(id, SDL_CONTROLLER_BUTTON_START, 1);
}

static void expect_quit(void)
{
    SDL_Event event = next();
    CHECK(event.type == SDL_QUIT);
}

static void test_keyboard_and_peek(void)
{
    SDL_Event event;
    reset(0);
    keyboard(SDL_KEYDOWN, SDLK_q, SDL_SCANCODE_Q, KMOD_LSHIFT);
    CHECK(SDL_PollEvent(NULL) == 1);
    CHECK(SDL_PollEvent(NULL) == 1);
    event = next();
    CHECK(event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_q);
    CHECK(event.key.keysym.mod == KMOD_LSHIFT && event.key.windowID == 987);
    keyboard(SDL_KEYUP, SDLK_q, SDL_SCANCODE_Q, KMOD_LSHIFT);
    event = next();
    CHECK(event.type == SDL_KEYUP && event.key.keysym.sym == SDLK_q);
    empty();
    CHECK(SDL_PollEvent(NULL) == 0);
    passed("physical keyboard and PollEvent(NULL) preserve queued events");
}

static void test_inactive_and_plain_y(void)
{
    reset(0);
    pass_button(11, SDL_CONTROLLER_BUTTON_BACK, 1);
    pass_button(11, SDL_CONTROLLER_BUTTON_Y, 1);
    pass_button(11, SDL_CONTROLLER_BUTTON_Y, 0);
    empty();
    reset(1);
    pass_button(11, SDL_CONTROLLER_BUTTON_Y, 1);
    pass_button(11, SDL_CONTROLLER_BUTTON_Y, 0);
    empty();
    passed("inactive text and Y without View leave controller input unchanged");
}

static void test_name_same_controller(void)
{
    SDL_Event event;
    reset(1);
    pass_button(11, SDL_CONTROLLER_BUTTON_BACK, 1);
    pass_button(22, SDL_CONTROLLER_BUTTON_Y, 1);
    pass_button(22, SDL_CONTROLLER_BUTTON_Y, 0);
    button(11, SDL_CONTROLLER_BUTTON_Y, 1);
    /* A physical key queued afterward must follow the entire replacement. */
    keyboard(SDL_KEYDOWN, SDLK_p, SDL_SCANCODE_P, KMOD_NONE);
    read_name(NULL, 0);
    event = next();
    CHECK(event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_p);
    CHECK(event.key.windowID == 987);
    button(11, SDL_CONTROLLER_BUTTON_Y, 0);
    empty();
    passed("same-device View+Y returns ordered Ctrl+A and UTF-8 text without Enter");
}

static void test_debounce_and_replacement(void)
{
    char first[32];
    char second[32];
    reset(1);
    pass_button(11, SDL_CONTROLLER_BUTTON_BACK, 1);
    button(11, SDL_CONTROLLER_BUTTON_Y, 1);
    read_name(first, 0);
    button(11, SDL_CONTROLLER_BUTTON_Y, 1);
    button(11, SDL_CONTROLLER_BUTTON_Y, 1);
    empty();
    button(11, SDL_CONTROLLER_BUTTON_Y, 0);
    empty();
    button(11, SDL_CONTROLLER_BUTTON_Y, 1);
    read_name(second, 0);
    CHECK(strcmp(first, second) != 0);
    /* Release remains consumed even if View and the text field went away. */
    pass_button(11, SDL_CONTROLLER_BUTTON_BACK, 0);
    SDL_StopTextInput();
    button(11, SDL_CONTROLLER_BUTTON_Y, 0);
    empty();
    pass_button(11, SDL_CONTROLLER_BUTTON_Y, 1);
    pass_button(11, SDL_CONTROLLER_BUTTON_Y, 0);
    passed("held Y is debounced; another tap changes name; paired release is consumed");
}

static void test_held_physical_control(void)
{
    reset(1);
    SDL_SetModState(KMOD_RCTRL);
    pass_button(11, SDL_CONTROLLER_BUTTON_BACK, 1);
    button(11, SDL_CONTROLLER_BUTTON_Y, 1);
    read_name(NULL, 1);
    CHECK(SDL_GetModState() == KMOD_RCTRL);
    button(11, SDL_CONTROLLER_BUTTON_Y, 0);
    empty();
    passed("an already-held physical Ctrl is never synthetically released");
}

static void test_y_before_view(void)
{
    reset(1);
    pass_button(11, SDL_CONTROLLER_BUTTON_Y, 1);
    pass_button(11, SDL_CONTROLLER_BUTTON_BACK, 1);
    pass_button(11, SDL_CONTROLLER_BUTTON_Y, 1);
    pass_button(11, SDL_CONTROLLER_BUTTON_Y, 0);
    button(11, SDL_CONTROLLER_BUTTON_Y, 1);
    read_name(NULL, 0);
    button(11, SDL_CONTROLLER_BUTTON_Y, 0);
    empty();
    passed("Y held before View needs a fresh tap before generating a name");
}

static void test_idle_quit_and_rearm(void)
{
    reset(0);
    hold(11);
    ticks(3999);
    empty();
    ticks(4000);
    expect_quit();
    empty();
    ticks(14000);
    empty();
    pass_button(11, SDL_CONTROLLER_BUTTON_START, 0);
    ticks(15000);
    pass_button(11, SDL_CONTROLLER_BUTTON_START, 1);
    ticks(18000);
    expect_quit();
    empty();
    passed("idle polling quits at 3000 ms once per hold and rearms only after release");
}

static void test_quit_same_device(void)
{
    reset(0);
    pass_button(11, SDL_CONTROLLER_BUTTON_BACK, 1);
    pass_button(22, SDL_CONTROLLER_BUTTON_START, 1);
    ticks(9000);
    empty();
    pass_button(11, SDL_CONTROLLER_BUTTON_START, 1);
    ticks(11999);
    empty();
    ticks(12000);
    expect_quit();
    empty();
    passed("View and Menu on different controllers cannot request quit");
}

static void test_release_cancels_quit(void)
{
    reset(0);
    hold(11);
    ticks(4001);
    pass_button(11, SDL_CONTROLLER_BUTTON_START, 0);
    empty();
    ticks(12000);
    empty();
    passed("a queued release cancels the hold before its deadline is evaluated");
}

static void test_removed_devices(void)
{
    static const Uint32 kinds[] = {
        SDL_CONTROLLERDEVICEREMOVED, SDL_JOYDEVICEREMOVED, SDL_CONTROLLERDEVICEREMAPPED
    };
    unsigned i;
    for (i = 0; i < sizeof(kinds) / sizeof(kinds[0]); ++i) {
        SDL_Event event;
        reset(1);
        hold(11);
        memset(&event, 0, sizeof(event));
        event.type = kinds[i];
        if (kinds[i] == SDL_JOYDEVICEREMOVED)
            event.jdevice.which = 11;
        else
            event.cdevice.which = 11;
        push(&event);
        event = next();
        /*
         * SDL 2.30's GameControllerEventWatcher emits CONTROLLERDEVICEREMOVED
         * before every JOYDEVICEREMOVED, even for an unopened synthetic ID.
         * SDL 2.0.20 only did that for an opened controller. Accept this exact
         * same-device pair, but do not hide unrelated events or a stray quit.
         */
        if (kinds[i] == SDL_JOYDEVICEREMOVED
            && event.type == SDL_CONTROLLERDEVICEREMOVED) {
            CHECK(event.cdevice.which == 11);
            event = next();
        }
        if (event.type != kinds[i])
            fprintf(stderr, "Removal event: expected 0x%x, received 0x%x\n",
                (unsigned)kinds[i], (unsigned)event.type);
        CHECK(event.type == kinds[i]);
        if (kinds[i] == SDL_JOYDEVICEREMOVED)
            CHECK(event.jdevice.which == 11);
        else
            CHECK(event.cdevice.which == 11);
        ticks(9000);
        empty();
        pass_button(11, SDL_CONTROLLER_BUTTON_Y, 1);
        pass_button(11, SDL_CONTROLLER_BUTTON_Y, 0);
        pass_button(11, SDL_CONTROLLER_BUTTON_START, 1);
        ticks(12000);
        empty();
    }
    passed("controller removal, joystick removal and remapping clear stale holds");
}

static void test_focus_resets(void)
{
    static const Uint8 windows[] = {
        SDL_WINDOWEVENT_FOCUS_LOST, SDL_WINDOWEVENT_HIDDEN,
        SDL_WINDOWEVENT_MINIMIZED, SDL_WINDOWEVENT_CLOSE
    };
    static const Uint32 apps[] = {
        SDL_APP_TERMINATING, SDL_APP_WILLENTERBACKGROUND, SDL_APP_DIDENTERBACKGROUND
    };
    unsigned i;
    for (i = 0; i < sizeof(windows) / sizeof(windows[0]); ++i) {
        SDL_Event event;
        reset(1);
        hold(11);
        memset(&event, 0, sizeof(event));
        event.type = SDL_WINDOWEVENT;
        event.window.event = windows[i];
        push(&event);
        event = next();
        CHECK(event.type == SDL_WINDOWEVENT && event.window.event == windows[i]);
        ticks(9000);
        empty();
        pass_button(11, SDL_CONTROLLER_BUTTON_Y, 1);
        pass_button(11, SDL_CONTROLLER_BUTTON_Y, 0);
    }
    for (i = 0; i < sizeof(apps) / sizeof(apps[0]); ++i) {
        SDL_Event event;
        reset(0);
        hold(11);
        memset(&event, 0, sizeof(event));
        event.type = apps[i];
        push(&event);
        event = next();
        CHECK(event.type == apps[i]);
        ticks(9000);
        empty();
    }
    passed("focus loss, hiding, minimization, closing and background events reset holds");
}

static void test_tick_wraparound(void)
{
    reset(0);
    ticks(UINT32_MAX - 999u);
    hold(11);
    ticks(1999);
    empty();
    ticks(2000);
    expect_quit();
    empty();
    passed("three-second hold handles SDL's 32-bit tick wraparound");
}

static void test_quit_peek_and_many_devices(void)
{
    SDL_Event event;
    reset(0);
    hold(11);
    hold(22);
    hold(33);
    ticks(4000);
    CHECK(SDL_PollEvent(NULL) == 0); /* A pure peek cannot advance input state. */
    keyboard(SDL_KEYDOWN, SDLK_q, SDL_SCANCODE_Q, KMOD_NONE);
    event = next();
    CHECK(event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_q);
    CHECK(SDL_PollEvent(NULL) == 0);
    expect_quit();
    empty();
    passed("peek does not advance holds; simultaneous holds produce just one quit");
}

static void test_event_passthrough(void)
{
    SDL_Event event;
    reset(1);
    memset(&event, 0, sizeof(event));
    event.type = SDL_CONTROLLERAXISMOTION;
    event.caxis.which = 11;
    event.caxis.axis = SDL_CONTROLLER_AXIS_LEFTX;
    event.caxis.value = -12345;
    push(&event);
    event = next();
    CHECK(event.type == SDL_CONTROLLERAXISMOTION && event.caxis.value == -12345);
    memset(&event, 0, sizeof(event));
    event.type = SDL_JOYBUTTONDOWN;
    event.jbutton.which = 11;
    event.jbutton.button = SDL_CONTROLLER_BUTTON_BACK;
    push(&event);
    event = next();
    CHECK(event.type == SDL_JOYBUTTONDOWN);
    pass_button(11, SDL_CONTROLLER_BUTTON_Y, 1);
    pass_button(11, SDL_CONTROLLER_BUTTON_Y, 0);
    pass_button(11, SDL_CONTROLLER_BUTTON_A, 1);
    pass_button(11, SDL_CONTROLLER_BUTTON_A, 0);
    hold(11);
    memset(&event, 0, sizeof(event));
    event.type = SDL_QUIT;
    push(&event);
    expect_quit();
    ticks(9000);
    empty();
    passed("axis, raw joystick, other buttons and native quit pass through unchanged");
}

static void test_capacity_fails_open(void)
{
    SDL_JoystickID id;
    reset(1);
    for (id = 100; id < 117; ++id)
        pass_button(id, SDL_CONTROLLER_BUTTON_BACK, 1);
    pass_button(116, SDL_CONTROLLER_BUTTON_Y, 1);
    pass_button(116, SDL_CONTROLLER_BUTTON_Y, 0);
    button(100, SDL_CONTROLLER_BUTTON_Y, 1);
    read_name(NULL, 0);
    button(100, SDL_CONTROLLER_BUTTON_Y, 0);
    empty();
    passed("full controller tracking table passes through input without evicting held devices");
}

static void test_modal_exit(void)
{
    reset(1);
    hold(11);
    ticks(4000);
    expect_quit();
    empty();
    CHECK(SDL_IsTextInputActive() == SDL_TRUE);
    passed("quit works with text input active without typing or confirming a field");
}

int main(void)
{
    SDL_Window *window;
    CHECK(SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS | SDL_INIT_GAMECONTROLLER) == 0);
    window = SDL_CreateWindow("MES input tests", SDL_WINDOWPOS_UNDEFINED,
        SDL_WINDOWPOS_UNDEFINED, 64, 64, SDL_WINDOW_HIDDEN);
    CHECK(window != NULL);
    test_keyboard_and_peek();
    test_inactive_and_plain_y();
    test_name_same_controller();
    test_debounce_and_replacement();
    test_held_physical_control();
    test_y_before_view();
    test_idle_quit_and_rearm();
    test_quit_same_device();
    test_release_cancels_quit();
    test_removed_devices();
    test_focus_resets();
    test_tick_wraparound();
    test_quit_peek_and_many_devices();
    test_event_passthrough();
    test_capacity_fails_open();
    test_modal_exit();
    SDL_StopTextInput();
    SDL_DestroyWindow(window);
    SDL_Quit();
    printf("1..%u\n", tests);
    return 0;
}
#endif
