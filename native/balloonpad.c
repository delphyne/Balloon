/*
 * balloonpad: a tiny native Lua module that lets Balloon see the gamepad.
 *
 * Windower 4's Lua event model only delivers keyboard and mouse input, so an
 * addon cannot tell when the player advances dialogue with a controller.
 * Windower does, however, let addons load native Lua C modules through
 * package.cpath (XIPivot does this), and LuaCore.dll exports the Lua 5.1 C
 * API. This module polls XInput directly, so it needs no changes to the
 * game's controller bindings.
 *
 *   local pad = require('balloonpad')
 *   local connected, buttons, pressed, released, slot = pad.poll()
 *
 * `buttons` is the XInput wButtons bitmask for the current frame, `pressed`
 * and `released` are the bits that changed since the previous poll, and
 * `slot` is the XInput user index that answered (0-3). Call it once per
 * frame from prerender.
 *
 * Build with `make native` (mingw-w64, 32-bit, linked against Windower's
 * LuaCore.dll); the result goes to libs/balloonpad.dll.
 */
#include <windows.h>
#include <xinput.h>

#include "lua.h"
#include "lauxlib.h"

static int slot = -1;              /* last slot that reported a controller */
static WORD last_buttons = 0;
static unsigned rescan_counter = 0;

/* XInputGetState is slow for empty slots, so once nothing is connected we
 * only look again every RESCAN_EVERY polls (about a second at 60 fps). */
#define RESCAN_EVERY 60

static int l_poll(lua_State *L)
{
    XINPUT_STATE state;
    DWORD result = ERROR_DEVICE_NOT_CONNECTED;

    if (slot >= 0) {
        ZeroMemory(&state, sizeof(state));
        result = XInputGetState((DWORD)slot, &state);
        if (result != ERROR_SUCCESS) {
            slot = -1;
        }
    }

    if (slot < 0 && (rescan_counter++ % RESCAN_EVERY) == 0) {
        DWORD i;
        for (i = 0; i < XUSER_MAX_COUNT; i++) {
            ZeroMemory(&state, sizeof(state));
            if (XInputGetState(i, &state) == ERROR_SUCCESS) {
                slot = (int)i;
                result = ERROR_SUCCESS;
                break;
            }
        }
    }

    if (result != ERROR_SUCCESS) {
        last_buttons = 0;
        lua_pushboolean(L, 0);
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        lua_pushinteger(L, -1);
        return 5;
    }

    {
        WORD buttons = state.Gamepad.wButtons;
        WORD pressed = (WORD)(buttons & (WORD)~last_buttons);
        WORD released = (WORD)(last_buttons & (WORD)~buttons);
        last_buttons = buttons;

        lua_pushboolean(L, 1);
        lua_pushinteger(L, buttons);
        lua_pushinteger(L, pressed);
        lua_pushinteger(L, released);
        lua_pushinteger(L, slot);
        return 5;
    }
}

static const luaL_Reg functions[] = {
    {"poll", l_poll},
    {NULL, NULL}
};

__declspec(dllexport) int luaopen_balloonpad(lua_State *L)
{
    luaL_register(L, "balloonpad", functions);
    return 1;
}
