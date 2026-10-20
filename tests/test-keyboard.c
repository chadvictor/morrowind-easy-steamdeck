/* Real SDL2 integration tests for the opt-in visual keyboard input backend. */
#define _GNU_SOURCE
#include <SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../native/keyboard-layout.h"

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "FAIL keyboard line %d: %s\n", __LINE__, #condition); exit(1); \
} } while (0)

static SDL_Event captured[2048];
static unsigned count;
static unsigned tests;
static int selection = 15, visible, shifted, caps, active;

static int snapshot(const SDL_Event *event)
{
    return event->type == SDL_KEYUP && event->key.keysym.scancode >= 400
        && event->key.keysym.scancode <= 499 && (event->key.keysym.mod & KMOD_GUI) != 0;
}

static void collect(void)
{
    unsigned zeros = 0, attempts;
    for (attempts = 0; attempts < 2048 && zeros < 3; ++attempts) {
        SDL_Event event;
        if (SDL_PollEvent(&event) == 0) {
            ++zeros;
            continue;
        }
        zeros = 0;
        CHECK(count < sizeof(captured) / sizeof(captured[0]));
        captured[count++] = event;
        if (snapshot(&event)) {
            int code = event.key.keysym.scancode;
            CHECK(event.key.keysym.sym == SDL_SCANCODE_TO_KEYCODE(code));
            CHECK(event.key.repeat == 0);
            CHECK(code == 499 || code < 400 + MES_KEYBOARD_KEY_COUNT);
            visible = code != 499;
            if (visible)
                selection = code - 400;
            shifted = (event.key.keysym.mod & KMOD_SHIFT) != 0;
            caps = (event.key.keysym.mod & KMOD_CTRL) != 0;
            active = (event.key.keysym.mod & KMOD_ALT) != 0;
        }
    }
    CHECK(zeros == 3);
}

static void clear(void) { count = 0; }
static void push(SDL_Event *event) { CHECK(SDL_PushEvent(event) == 1); }
static void ticks(Uint32 value)
{
    char buffer[32];
    (void)snprintf(buffer, sizeof(buffer), "%u", (unsigned)value);
    CHECK(setenv("MES_TEST_TICKS", buffer, 1) == 0);
    CHECK(SDL_GetTicks() == value);
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
    collect();
}
static void tap(SDL_JoystickID id, Uint8 value)
{
    button(id, value, 1);
    button(id, value, 0);
}
static void axis(SDL_JoystickID id, Uint8 value, Sint16 position)
{
    SDL_Event event;
    memset(&event, 0, sizeof(event));
    event.type = SDL_CONTROLLERAXISMOTION;
    event.caxis.which = id;
    event.caxis.axis = value;
    event.caxis.value = position;
    push(&event);
    collect();
}
static void only_snapshots(void)
{
    unsigned i;
    for (i = 0; i < count; ++i) {
        if (!snapshot(&captured[i]))
            fprintf(stderr, "Unexpected captured type 0x%x\n", (unsigned)captured[i].type);
        CHECK(snapshot(&captured[i]));
    }
}
static void no_controller_events(void)
{
    unsigned i;
    for (i = 0; i < count; ++i)
        CHECK(captured[i].type != SDL_CONTROLLERBUTTONDOWN
            && captured[i].type != SDL_CONTROLLERBUTTONUP
            && captured[i].type != SDL_CONTROLLERAXISMOTION);
}
static void expect_text(const char *text)
{
    unsigned i, texts = 0;
    for (i = 0; i < count; ++i) {
        if (snapshot(&captured[i]))
            continue;
        CHECK(captured[i].type == SDL_TEXTINPUT);
        CHECK(strcmp(captured[i].text.text, text) == 0);
        ++texts;
    }
    CHECK(texts == 1);
}
static void expect_edit(SDL_Keycode key)
{
    unsigned i, edits = 0;
    for (i = 0; i < count; ++i) {
        if (snapshot(&captured[i]))
            continue;
        CHECK(captured[i].type == (Uint32)(edits == 0 ? SDL_KEYDOWN : SDL_KEYUP));
        CHECK(captured[i].key.keysym.sym == key);
        ++edits;
    }
    CHECK(edits == 2);
}
static void passed(const char *label) { printf("ok %u - %s\n", ++tests, label); }

static void reset(int text)
{
    SDL_Event event;
    memset(&event, 0, sizeof(event));
    event.type = SDL_WINDOWEVENT;
    event.window.event = SDL_WINDOWEVENT_FOCUS_LOST;
    push(&event);
    collect();
    SDL_FlushEvents(SDL_FIRSTEVENT, SDL_LASTEVENT);
    SDL_SetModState(KMOD_NONE);
    SDL_StopTextInput();
    if (text)
        SDL_StartTextInput();
    ticks(1000);
    visible = 0;
    clear();
}
static void open_keyboard(SDL_JoystickID id)
{
    button(id, SDL_CONTROLLER_BUTTON_BACK, 1);
    button(id, SDL_CONTROLLER_BUTTON_X, 1);
    CHECK(visible);
    button(id, SDL_CONTROLLER_BUTTON_X, 0);
    button(id, SDL_CONTROLLER_BUTTON_BACK, 0);
}
static void select_key(unsigned target)
{
    static const unsigned first[] = { 0, 14, 28, 41, 53 };
    unsigned row, i;
    CHECK(visible && target < MES_KEYBOARD_KEY_COUNT);
    row = (unsigned)mes_keyboard_keys[selection].row;
    for (i = 0; i < row; ++i)
        tap(11, SDL_CONTROLLER_BUTTON_DPAD_UP);
    while (selection != 0)
        tap(11, SDL_CONTROLLER_BUTTON_DPAD_LEFT);
    row = (unsigned)mes_keyboard_keys[target].row;
    for (i = 0; i < row; ++i)
        tap(11, SDL_CONTROLLER_BUTTON_DPAD_DOWN);
    CHECK(selection == (int)first[row]);
    for (i = first[row]; i < target; ++i)
        tap(11, SDL_CONTROLLER_BUTTON_DPAD_RIGHT);
    CHECK(selection == (int)target);
    clear();
}

static void test_view_and_inactive(void)
{
    reset(0);
    button(11, SDL_CONTROLLER_BUTTON_BACK, 1);
    CHECK(count == 0);
    button(11, SDL_CONTROLLER_BUTTON_BACK, 0);
    CHECK(count == 2);
    CHECK(captured[0].type == SDL_CONTROLLERBUTTONDOWN);
    CHECK(captured[1].type == SDL_CONTROLLERBUTTONUP);
    CHECK(captured[0].cbutton.button == SDL_CONTROLLER_BUTTON_BACK);
    clear();
    open_keyboard(11);
    CHECK(visible && !active);
    only_snapshots();
    clear();
    tap(11, SDL_CONTROLLER_BUTTON_A);
    tap(11, SDL_CONTROLLER_BUTTON_X);
    tap(11, SDL_CONTROLLER_BUTTON_LEFTSHOULDER);
    tap(11, SDL_CONTROLLER_BUTTON_RIGHTSHOULDER);
    only_snapshots();
    SDL_StartTextInput();
    collect();
    CHECK(active);
    only_snapshots();
    SDL_StopTextInput();
    collect();
    CHECK(!active);
    clear();
    tap(11, SDL_CONTROLLER_BUTTON_B);
    CHECK(!visible);
    only_snapshots();
    passed("View tap is deferred; View+X opens without Journal; inactive fields cannot be edited");
}

static void test_name_compatibility(void)
{
    unsigned i, text_count = 0;
    reset(1);
    button(11, SDL_CONTROLLER_BUTTON_BACK, 1);
    tap(11, SDL_CONTROLLER_BUTTON_Y);
    button(11, SDL_CONTROLLER_BUTTON_BACK, 0);
    CHECK(!visible && count == 5);
    no_controller_events();
    for (i = 0; i < count; ++i)
        if (captured[i].type == SDL_TEXTINPUT) {
            CHECK(strchr(captured[i].text.text, ' ') != NULL);
            ++text_count;
        }
    CHECK(text_count == 1);
    clear();
    open_keyboard(11);
    clear();
    button(11, SDL_CONTROLLER_BUTTON_BACK, 1);
    tap(11, SDL_CONTROLLER_BUTTON_Y);
    button(11, SDL_CONTROLLER_BUTTON_BACK, 0);
    CHECK(visible && shifted);
    only_snapshots();
    tap(11, SDL_CONTROLLER_BUTTON_B);
    passed("View+Y names still work when closed; Y becomes Shift while the keyboard is open");
}

static void test_navigation(void)
{
    reset(1);
    open_keyboard(11);
    select_key(0);
    tap(11, SDL_CONTROLLER_BUTTON_DPAD_LEFT);
    CHECK(selection == 13);
    tap(11, SDL_CONTROLLER_BUTTON_DPAD_RIGHT);
    CHECK(selection == 0);
    tap(11, SDL_CONTROLLER_BUTTON_DPAD_UP);
    CHECK(selection == 0);
    select_key(13);
    tap(11, SDL_CONTROLLER_BUTTON_DPAD_DOWN); CHECK(selection == 27);
    tap(11, SDL_CONTROLLER_BUTTON_DPAD_DOWN); CHECK(selection == 40);
    tap(11, SDL_CONTROLLER_BUTTON_DPAD_DOWN); CHECK(selection == 52);
    tap(11, SDL_CONTROLLER_BUTTON_DPAD_DOWN); CHECK(selection == 59);
    tap(11, SDL_CONTROLLER_BUTTON_DPAD_DOWN); CHECK(selection == 59);
    tap(11, SDL_CONTROLLER_BUTTON_DPAD_UP); CHECK(selection == 52);
    only_snapshots();
    passed("row edges wrap horizontally; vertical navigation uses the nearest key center");
}

static void test_repeat_and_heartbeat(void)
{
    reset(1);
    open_keyboard(11);
    select_key(0);
    button(11, SDL_CONTROLLER_BUTTON_DPAD_RIGHT, 1);
    CHECK(selection == 1);
    clear(); ticks(1349); collect(); CHECK(count == 0);
    ticks(1350); collect(); CHECK(selection == 2);
    clear(); ticks(1439); collect(); CHECK(count == 0);
    ticks(1440); collect(); CHECK(selection == 3);
    clear(); ticks(2000);
    button(11, SDL_CONTROLLER_BUTTON_DPAD_RIGHT, 0);
    CHECK(selection == 3);
    only_snapshots();
    clear(); ticks(3000); collect();
    CHECK(count == 1 && snapshot(&captured[0]) && selection == 3);
    clear(); collect(); CHECK(count == 0);
    passed("D-pad repeats after 350 ms then every 90 ms; release beats timers; heartbeat is bounded");
}

static void test_typing_and_modifiers(void)
{
    reset(1);
    open_keyboard(11);
    if (caps) { select_key(28); tap(11, SDL_CONTROLLER_BUTTON_A); }
    select_key(15);
    tap(11, SDL_CONTROLLER_BUTTON_A); expect_text("q");
    clear(); tap(11, SDL_CONTROLLER_BUTTON_Y); CHECK(shifted);
    clear(); tap(11, SDL_CONTROLLER_BUTTON_A); expect_text("Q"); CHECK(!shifted);
    clear(); tap(11, SDL_CONTROLLER_BUTTON_A); expect_text("q");
    select_key(28); tap(11, SDL_CONTROLLER_BUTTON_A); CHECK(caps);
    select_key(29); tap(11, SDL_CONTROLLER_BUTTON_A); expect_text("A");
    clear(); tap(11, SDL_CONTROLLER_BUTTON_Y);
    clear(); tap(11, SDL_CONTROLLER_BUTTON_A); expect_text("a"); CHECK(caps && !shifted);
    select_key(1); tap(11, SDL_CONTROLLER_BUTTON_A); expect_text("1");
    clear(); tap(11, SDL_CONTROLLER_BUTTON_Y);
    clear(); tap(11, SDL_CONTROLLER_BUTTON_A); expect_text("!");
    select_key(27); tap(11, SDL_CONTROLLER_BUTTON_Y);
    clear(); tap(11, SDL_CONTROLLER_BUTTON_A); expect_text("|");
    select_key(39); tap(11, SDL_CONTROLLER_BUTTON_Y);
    clear(); tap(11, SDL_CONTROLLER_BUTTON_A); expect_text("\"");
    CHECK(SDL_GetModState() == KMOD_NONE);
    select_key(28); tap(11, SDL_CONTROLLER_BUTTON_A); CHECK(!caps);
    passed("ASCII US text, punctuation, persistent Caps and one-shot Shift do not alter physical modifiers");
}

static void test_edit_actions(void)
{
    reset(1);
    open_keyboard(11);
    clear(); tap(11, SDL_CONTROLLER_BUTTON_X); expect_edit(SDLK_BACKSPACE);
    clear(); tap(11, SDL_CONTROLLER_BUTTON_LEFTSHOULDER); expect_edit(SDLK_LEFT);
    clear(); tap(11, SDL_CONTROLLER_BUTTON_RIGHTSHOULDER); expect_edit(SDLK_RIGHT);
    select_key(14); tap(11, SDL_CONTROLLER_BUTTON_A); expect_edit(SDLK_TAB);
    select_key(56); tap(11, SDL_CONTROLLER_BUTTON_A); expect_edit(SDLK_HOME);
    select_key(57); tap(11, SDL_CONTROLLER_BUTTON_A); expect_edit(SDLK_END);
    select_key(58); tap(11, SDL_CONTROLLER_BUTTON_A); expect_edit(SDLK_DELETE);
    select_key(54); tap(11, SDL_CONTROLLER_BUTTON_Y);
    clear(); tap(11, SDL_CONTROLLER_BUTTON_A); expect_text(" "); CHECK(!shifted);
    passed("Backspace, caret, Tab, Home, End, Delete and Space produce bounded edit events");
}

static void test_owner_and_late_releases(void)
{
    reset(1);
    open_keyboard(11);
    select_key(15);
    tap(22, SDL_CONTROLLER_BUTTON_DPAD_RIGHT);
    tap(22, SDL_CONTROLLER_BUTTON_A);
    tap(22, SDL_CONTROLLER_BUTTON_Y);
    tap(22, SDL_CONTROLLER_BUTTON_B);
    button(22, SDL_CONTROLLER_BUTTON_BACK, 1);
    button(22, SDL_CONTROLLER_BUTTON_X, 1);
    CHECK(selection == 15 && visible && !shifted);
    only_snapshots();
    clear();
    button(11, SDL_CONTROLLER_BUTTON_B, 1);
    CHECK(!visible);
    button(11, SDL_CONTROLLER_BUTTON_B, 1); /* Duplicate held down must not leak. */
    button(22, SDL_CONTROLLER_BUTTON_X, 0);
    button(22, SDL_CONTROLLER_BUTTON_BACK, 0);
    button(11, SDL_CONTROLLER_BUTTON_B, 0);
    only_snapshots();
    clear(); tap(11, SDL_CONTROLLER_BUTTON_A);
    CHECK(count == 2 && captured[0].type == SDL_CONTROLLERBUTTONDOWN
        && captured[1].type == SDL_CONTROLLERBUTTONUP);
    passed("only the opening controller types; captured button releases cannot activate the underlying UI");
}

static void test_done_and_enter(void)
{
    reset(1);
    open_keyboard(11);
    select_key(59);
    button(11, SDL_CONTROLLER_BUTTON_A, 1);
    CHECK(!visible);
    button(11, SDL_CONTROLLER_BUTTON_A, 0);
    only_snapshots();
    clear(); open_keyboard(11);
    select_key(40);
    button(11, SDL_CONTROLLER_BUTTON_A, 1);
    CHECK(!visible);
    button(11, SDL_CONTROLLER_BUTTON_A, 0);
    expect_edit(SDLK_RETURN);
    clear(); open_keyboard(11); clear();
    tap(11, SDL_CONTROLLER_BUTTON_START);
    CHECK(!visible); only_snapshots();
    passed("Done and Menu close without confirmation; the Enter key explicitly confirms then closes");
}

static void test_physical_keyboard_and_escape(void)
{
    SDL_Event event;
    reset(1);
    open_keyboard(11);
    clear();
    memset(&event, 0, sizeof(event));
    event.type = SDL_TEXTINPUT;
    (void)snprintf(event.text.text, sizeof(event.text.text), "%s", "physical");
    push(&event); collect(); expect_text("physical");
    clear();
    memset(&event, 0, sizeof(event));
    event.type = SDL_KEYDOWN;
    event.key.keysym.sym = SDLK_ESCAPE;
    event.key.keysym.scancode = SDL_SCANCODE_ESCAPE;
    push(&event); collect(); CHECK(!visible); only_snapshots();
    event.type = SDL_KEYUP;
    push(&event); collect(); only_snapshots();
    clear();
    event.type = SDL_KEYDOWN;
    push(&event); collect(); CHECK(count == 1 && captured[0].type == SDL_KEYDOWN);
    passed("physical text remains available; Escape closes just the overlay and consumes its paired release");
}

static void test_axes_and_neutralization(void)
{
    unsigned i, zeros = 0;
    reset(1);
    axis(11, SDL_CONTROLLER_AXIS_LEFTX, 20000);
    CHECK(count == 1 && captured[0].caxis.value == 20000);
    clear(); open_keyboard(11);
    for (i = 0; i < count; ++i) {
        if (snapshot(&captured[i]))
            continue;
        CHECK(captured[i].type == SDL_CONTROLLERAXISMOTION && captured[i].caxis.value == 0);
        ++zeros;
    }
    CHECK(zeros == 1);
    clear(); axis(11, SDL_CONTROLLER_AXIS_LEFTX, 0);
    select_key(15);
    axis(11, SDL_CONTROLLER_AXIS_LEFTX, 16000); CHECK(selection == 16);
    axis(11, SDL_CONTROLLER_AXIS_LEFTY, 25000); CHECK(selection == 30);
    only_snapshots();
    clear(); tap(11, SDL_CONTROLLER_BUTTON_B); CHECK(!visible);
    axis(11, SDL_CONTROLLER_AXIS_LEFTX, 22000);
    only_snapshots();
    clear(); axis(11, SDL_CONTROLLER_AXIS_LEFTX, 0);
    CHECK(count == 1 && captured[0].type == SDL_CONTROLLERAXISMOTION && captured[0].caxis.value == 0);
    clear(); axis(11, SDL_CONTROLLER_AXIS_LEFTX, -20000);
    CHECK(count == 1 && captured[0].caxis.value == -20000);
    passed("opening neutralizes old axes; left-stick navigation follows its dominant axis and requires recenter after close");
}

static void test_resets(void)
{
    SDL_Event event;
    unsigned i;
    reset(1); open_keyboard(11); clear();
    button(11, SDL_CONTROLLER_BUTTON_DPAD_RIGHT, 1);
    clear();
    memset(&event, 0, sizeof(event));
    event.type = SDL_WINDOWEVENT;
    event.window.event = SDL_WINDOWEVENT_FOCUS_LOST;
    push(&event); collect(); CHECK(!visible);
    clear(); button(11, SDL_CONTROLLER_BUTTON_DPAD_RIGHT, 0); CHECK(count == 0);
    open_keyboard(11); clear();
    button(11, SDL_CONTROLLER_BUTTON_DPAD_RIGHT, 1); clear();
    memset(&event, 0, sizeof(event));
    event.type = SDL_CONTROLLERDEVICEREMOVED;
    event.cdevice.which = 11;
    push(&event); collect(); CHECK(!visible);
    clear(); button(11, SDL_CONTROLLER_BUTTON_DPAD_RIGHT, 0); CHECK(count == 0);
    ticks(20000); collect();
    for (i = 0; i < count; ++i) CHECK(captured[i].type != SDL_QUIT);
    passed("focus loss and disconnect close the overlay and retain release suppression without stale quit holds");
}

static void test_held_quit(void)
{
    unsigned i, quits = 0;
    reset(1); open_keyboard(11); clear();
    button(11, SDL_CONTROLLER_BUTTON_BACK, 1);
    button(11, SDL_CONTROLLER_BUTTON_START, 1);
    CHECK(visible);
    ticks(3999); collect(); CHECK(visible);
    button(11, SDL_CONTROLLER_BUTTON_START, 0); CHECK(visible);
    clear();
    ticks(5000); button(11, SDL_CONTROLLER_BUTTON_START, 1);
    ticks(8000); collect(); CHECK(!visible);
    for (i = 0; i < count; ++i)
        if (!snapshot(&captured[i])) { CHECK(captured[i].type == SDL_QUIT); ++quits; }
    CHECK(quits == 1);
    clear(); ticks(15000); collect(); CHECK(count == 0);
    button(11, SDL_CONTROLLER_BUTTON_START, 0);
    button(11, SDL_CONTROLLER_BUTTON_BACK, 0);
    CHECK(count == 0);
    passed("View+Menu remains a cancellable three-second quit while the keyboard is open");
}

static void test_snapshot_peek(void)
{
    SDL_Event event;
    unsigned attempts;
    reset(1);
    button(11, SDL_CONTROLLER_BUTTON_BACK, 1);
    memset(&event, 0, sizeof(event));
    event.type = SDL_CONTROLLERBUTTONDOWN;
    event.cbutton.which = 11;
    event.cbutton.button = SDL_CONTROLLER_BUTTON_X;
    event.cbutton.state = SDL_PRESSED;
    push(&event);
    for (attempts = 0; attempts < 4; ++attempts)
        if (SDL_PollEvent(&event) != 0)
            break;
    CHECK(attempts < 4 && snapshot(&event));
    /* This initial snapshot was consumed, so there must be no hidden repeat. */
    collect(); CHECK(count == 0);
    button(11, SDL_CONTROLLER_BUTTON_X, 0);
    button(11, SDL_CONTROLLER_BUTTON_BACK, 0);
    clear();
    button(11, SDL_CONTROLLER_BUTTON_Y, 1); /* Shift update only. */
    CHECK(shifted);
    clear();
    memset(&event, 0, sizeof(event));
    event.type = SDL_CONTROLLERBUTTONDOWN;
    event.cbutton.which = 11;
    event.cbutton.button = SDL_CONTROLLER_BUTTON_A;
    event.cbutton.state = SDL_PRESSED;
    /* Choose a printable key first; selection is retained between opens. */
    button(11, SDL_CONTROLLER_BUTTON_Y, 0);
    select_key(15);
    push(&event);
    for (attempts = 0; attempts < 4; ++attempts)
        if (SDL_PollEvent(&event) != 0)
            break;
    CHECK(attempts < 4 && event.type == SDL_TEXTINPUT);
    CHECK(SDL_PollEvent(NULL) == 1);
    CHECK(SDL_PollEvent(NULL) == 1);
    collect();
    CHECK(count == 1 && snapshot(&captured[0]) && !shifted);
    passed("synthetic text and following state snapshot preserve PollEvent(NULL) peek semantics");
}

static void test_toggle_and_quit_reset(void)
{
    SDL_Event event;
    reset(1);
    open_keyboard(11);
    clear();
    button(11, SDL_CONTROLLER_BUTTON_BACK, 1);
    button(11, SDL_CONTROLLER_BUTTON_X, 1);
    CHECK(!visible);
    button(11, SDL_CONTROLLER_BUTTON_X, 0);
    button(11, SDL_CONTROLLER_BUTTON_BACK, 0);
    only_snapshots();
    clear();
    open_keyboard(11);
    clear();
    memset(&event, 0, sizeof(event));
    event.type = SDL_QUIT;
    push(&event);
    collect();
    CHECK(!visible && count == 2);
    CHECK(captured[0].type == SDL_QUIT);
    CHECK(snapshot(&captured[1]) && captured[1].key.keysym.scancode == 499);
    clear();
    ticks(30000);
    collect();
    CHECK(count == 0);
    passed("View+X toggles without leaking releases; an external quit clears the overlay and its heartbeat");
}

static void test_neutralization_batch(void)
{
    SDL_Event event;
    unsigned device, axis_id, zero_axes = 0, released = 0, states = 0, i;
    reset(1);
    /* Free existing slots, then use all supported devices simultaneously. */
    for (device = 11; device <= 22; device += 11) {
        memset(&event, 0, sizeof(event));
        event.type = SDL_CONTROLLERDEVICEREMOVED;
        event.cdevice.which = (SDL_JoystickID)device;
        push(&event);
        collect();
    }
    clear();
    for (device = 100; device < 116; ++device) {
        button((SDL_JoystickID)device, SDL_CONTROLLER_BUTTON_A, 1);
        for (axis_id = 0; axis_id < SDL_CONTROLLER_AXIS_MAX; ++axis_id)
            axis((SDL_JoystickID)device, (Uint8)axis_id, 18000);
    }
    clear();
    open_keyboard(100);
    CHECK(visible);
    for (i = 0; i < count; ++i) {
        SDL_Event *current = &captured[i];
        if (snapshot(current)) {
            ++states;
        } else if (current->type == SDL_CONTROLLERAXISMOTION) {
            CHECK(current->caxis.value == 0);
            ++zero_axes;
        } else {
            CHECK(current->type == SDL_CONTROLLERBUTTONUP
                && current->cbutton.button == SDL_CONTROLLER_BUTTON_A);
            ++released;
        }
    }
    CHECK(zero_axes == 16 * SDL_CONTROLLER_AXIS_MAX && released == 16 && states >= 1);
    clear();
    tap(100, SDL_CONTROLLER_BUTTON_B);
    for (device = 100; device < 116; ++device)
        button((SDL_JoystickID)device, SDL_CONTROLLER_BUTTON_A, 0);
    CHECK(!visible);
    only_snapshots();
    passed("a 16-controller neutralization batch preserves all zero axes, releases and state snapshots");
}

int main(void)
{
    SDL_Window *window;
    CHECK(getenv("MES_VIRTUAL_KEYBOARD") != NULL);
    CHECK(SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS | SDL_INIT_GAMECONTROLLER) == 0);
    window = SDL_CreateWindow("MES keyboard tests", SDL_WINDOWPOS_UNDEFINED,
        SDL_WINDOWPOS_UNDEFINED, 64, 64, SDL_WINDOW_HIDDEN);
    CHECK(window != NULL);
    test_view_and_inactive();
    test_name_compatibility();
    test_navigation();
    test_repeat_and_heartbeat();
    test_typing_and_modifiers();
    test_edit_actions();
    test_owner_and_late_releases();
    test_done_and_enter();
    test_physical_keyboard_and_escape();
    test_axes_and_neutralization();
    test_resets();
    test_held_quit();
    test_snapshot_peek();
    test_toggle_and_quit_reset();
    test_neutralization_batch();
    SDL_StopTextInput();
    SDL_DestroyWindow(window);
    SDL_Quit();
    printf("1..%u\n", tests);
    return 0;
}
