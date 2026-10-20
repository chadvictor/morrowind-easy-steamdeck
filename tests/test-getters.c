/* Real virtual SDL joystick: polling getters must agree with captured events. */
#define _GNU_SOURCE
#include <SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "FAIL getters line %d: %s (%s)\n", __LINE__, #condition, SDL_GetError()); \
    exit(1); \
} } while (0)

static int opened;

static void drain(void)
{
    unsigned zeros = 0, attempts;
    for (attempts = 0; attempts < 2048 && zeros < 3; ++attempts) {
        SDL_Event event;
        if (!SDL_PollEvent(&event)) {
            ++zeros;
            continue;
        }
        zeros = 0;
        if (event.type == SDL_KEYUP && (event.key.keysym.mod & KMOD_GUI))
            opened = event.key.keysym.scancode != 499;
    }
    CHECK(zeros == 3);
}

static void button(SDL_JoystickID id, SDL_GameControllerButton value, int down)
{
    SDL_Event event;
    memset(&event, 0, sizeof(event));
    event.type = down ? SDL_CONTROLLERBUTTONDOWN : SDL_CONTROLLERBUTTONUP;
    event.cbutton.which = id;
    event.cbutton.button = (Uint8)value;
    event.cbutton.state = down ? SDL_PRESSED : SDL_RELEASED;
    CHECK(SDL_PushEvent(&event) == 1);
    drain();
}

static void update(void)
{
    SDL_JoystickUpdate();
    drain();
}

static int SDLCALL check_thread(void *data)
{
    SDL_GameController *controller = data;
    unsigned i;
    for (i = 0; i < 10000; ++i)
        if (SDL_GameControllerGetAxis(controller, SDL_CONTROLLER_AXIS_LEFTX) != 0
            || SDL_GameControllerGetButton(controller, SDL_CONTROLLER_BUTTON_A) != 0)
            return 1;
    return 0;
}

int main(void)
{
    SDL_Window *window;
    SDL_GameController *controller;
    SDL_Joystick *joystick;
    SDL_JoystickID id;
    int index, enabled, thread_result;
    SDL_Thread *thread;
    const char *value = getenv("MES_VIRTUAL_KEYBOARD");
    enabled = value != NULL && strcmp(value, "1") == 0;
    CHECK(SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1") == SDL_TRUE);
    CHECK(SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER) == 0);
    window = SDL_CreateWindow("MES getter tests", SDL_WINDOWPOS_UNDEFINED,
        SDL_WINDOWPOS_UNDEFINED, 64, 64, SDL_WINDOW_HIDDEN);
    CHECK(window != NULL);
    index = SDL_JoystickAttachVirtual(SDL_JOYSTICK_TYPE_GAMECONTROLLER,
        SDL_CONTROLLER_AXIS_MAX, SDL_CONTROLLER_BUTTON_MAX, 0);
    CHECK(index >= 0 && SDL_IsGameController(index));
    controller = SDL_GameControllerOpen(index);
    CHECK(controller != NULL);
    joystick = SDL_GameControllerGetJoystick(controller);
    CHECK(joystick != NULL);
    id = SDL_JoystickInstanceID(joystick);
    drain();
    SDL_StartTextInput();
    CHECK(SDL_JoystickSetVirtualAxis(joystick, SDL_CONTROLLER_AXIS_LEFTX, 20000) == 0);
    CHECK(SDL_JoystickSetVirtualButton(joystick, SDL_CONTROLLER_BUTTON_A, SDL_PRESSED) == 0);
    update();
    CHECK(SDL_GameControllerGetAxis(controller, SDL_CONTROLLER_AXIS_LEFTX) == 20000);
    CHECK(SDL_GameControllerGetButton(controller, SDL_CONTROLLER_BUTTON_A) == SDL_PRESSED);
    CHECK(SDL_JoystickSetVirtualButton(joystick, SDL_CONTROLLER_BUTTON_A, SDL_RELEASED) == 0);
    update();
    button(id, SDL_CONTROLLER_BUTTON_BACK, 1);
    button(id, SDL_CONTROLLER_BUTTON_X, 1);
    button(id, SDL_CONTROLLER_BUTTON_X, 0);
    button(id, SDL_CONTROLLER_BUTTON_BACK, 0);
    CHECK(opened == enabled);
    CHECK(SDL_JoystickSetVirtualButton(joystick, SDL_CONTROLLER_BUTTON_A, SDL_PRESSED) == 0);
    update();
    CHECK(SDL_JoystickGetAxis(joystick, SDL_CONTROLLER_AXIS_LEFTX) == 20000);
    CHECK(SDL_JoystickGetButton(joystick, SDL_CONTROLLER_BUTTON_A) == SDL_PRESSED);
    CHECK(SDL_GameControllerGetAxis(controller, SDL_CONTROLLER_AXIS_LEFTX) == (enabled ? 0 : 20000));
    CHECK(SDL_GameControllerGetButton(controller, SDL_CONTROLLER_BUTTON_A) == (enabled ? 0 : SDL_PRESSED));
    if (enabled) {
        thread = SDL_CreateThread(check_thread, "MES getter reader", controller);
        CHECK(thread != NULL);
        SDL_WaitThread(thread, &thread_result);
        CHECK(thread_result == 0);
    }
    button(id, SDL_CONTROLLER_BUTTON_B, 1);
    button(id, SDL_CONTROLLER_BUTTON_B, 0);
    CHECK(!opened);
    CHECK(SDL_GameControllerGetAxis(controller, SDL_CONTROLLER_AXIS_LEFTX) == (enabled ? 0 : 20000));
    CHECK(SDL_GameControllerGetButton(controller, SDL_CONTROLLER_BUTTON_A) == (enabled ? 0 : SDL_PRESSED));
    CHECK(SDL_JoystickSetVirtualAxis(joystick, SDL_CONTROLLER_AXIS_LEFTX, 0) == 0);
    CHECK(SDL_JoystickSetVirtualButton(joystick, SDL_CONTROLLER_BUTTON_A, SDL_RELEASED) == 0);
    update();
    CHECK(SDL_GameControllerGetAxis(controller, SDL_CONTROLLER_AXIS_LEFTX) == 0);
    CHECK(SDL_GameControllerGetButton(controller, SDL_CONTROLLER_BUTTON_A) == SDL_RELEASED);
    CHECK(SDL_JoystickSetVirtualAxis(joystick, SDL_CONTROLLER_AXIS_LEFTX, -20000) == 0);
    CHECK(SDL_JoystickSetVirtualButton(joystick, SDL_CONTROLLER_BUTTON_A, SDL_PRESSED) == 0);
    update();
    CHECK(SDL_GameControllerGetAxis(controller, SDL_CONTROLLER_AXIS_LEFTX) == -20000);
    CHECK(SDL_GameControllerGetButton(controller, SDL_CONTROLLER_BUTTON_A) == SDL_PRESSED);
    SDL_GameControllerClose(controller);
    CHECK(SDL_JoystickDetachVirtual(index) == 0);
    drain();
    SDL_DestroyWindow(window);
    SDL_Quit();
    printf("ok - SDL polling getters %s; underlying physical state remains unchanged\n",
        enabled ? "neutral during overlay and until release/recenter" : "pass through with feature disabled");
    return 0;
}
