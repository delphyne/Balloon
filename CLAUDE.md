# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Balloon is a Windower4 addon for Final Fantasy XI that replaces NPC dialogue in the chat log with an on-screen speech balloon (FFXIV-style), with optional NPC portraits, themes, animated text, and an advancement prompt. Originally by Hando (Japanese), English support by Yuki/Kenshi, themes/portraits by Ghosty. Comments in the Lua are a mix of Japanese and English. `readme.txt` is the user-facing doc and changelog (Japanese first, English second).

## Install

Windower runs under the Lumoria flatpak. Its install is at:

```
~/.var/app/net.windower.Lumoria/data/prefixes/prefix-1/pfx/drive_c/Windower4/
```

Like the sibling addons `../ahbuddy` and `../randommount`, this repo is meant to be symlinked from that folder's `addons/` directory so edits are live in game after a reload:

```
make install                           # find Windower and symlink this repo
make install WINDOWER=/path/Windower4  # if it is somewhere else
make where                             # print the folder it would use
make uninstall                         # remove the symlink
```

`make install` refuses to replace a real directory at `addons/Balloon`. At the time of writing that path *is* a real directory (an older copy), so move it aside first, keeping its `data/settings.xml` if the position/theme settings matter; copy that file into this repo's gitignored `data/` folder.

In game:

```
//lua load balloon      (first load)
//lua reload balloon    (after editing)
```

## Lint and tests

```
make check                     # lint and tests
luacheck .                     # lint alone
luajit test/test_Balloon.lua   # tests alone; Windower is stubbed
```

Keep the Makefile, `.luacheckrc`, and test harness in step with `../ahbuddy` and `../randommount`.

The test harness stubs `luau`, `texts`, `images`, `config`, `chat.chars`, `res`, and `windower`, then `dofile`s `Balloon.lua` and drives the `incoming text`, `addon command`, `keyboard`, and `prerender` handlers. It parses the real `themes/default/theme.xml` so `theme.lua` runs against shipped data. `Balloon.lua` keeps its state in locals, so tests observe results through the shared `ui` module (`require('ui')` returns the same table) and the stub widgets' recorded `_v` fields.

Windower's Lua accepts `"fmt":format(x)` (method call on a string literal). Standard luacheck/luajit do not parse it, so write `("fmt"):format(x)` instead. `.luacheckrc` whitelists the luau globals (`S`, `L`, `config`, `log`, `texts`, `images`, `res`, `chars`) and the `string`/`coroutine` extensions; add to it rather than sprinkling inline `-- luacheck:` comments.

## In-game debugging

- `//bl test <Name> : <message>` renders a test balloon without an NPC (mode 150, i.e. dialogue with a prompt).
- `//bl debug <off|all|mode|codes|chunk|process|wrap|chars|elements>` prints pipeline internals to the Windower console. `codes` dumps bytes of incoming text, which is how new control sequences are discovered.
- `//bl theme <name>` live-reloads a theme; `//bl portrait`, `//bl scale`, `//bl delay`, `//bl text_speed` are the other user-facing settings (full list in `readme.txt`).

## Architecture

Three Lua files form a pipeline; one XML file per theme drives layout.

**`Balloon.lua`** is the entry point and owns all event handlers and state (`balloon` table, `settings`). The core is the `incoming text` handler, which:
1. Filters by chat `mode` (150 NPC dialogue, 151 system, 144 promptless NPC, 142 battle). Emotes (mode 15) were deliberately removed from the accepted list.
2. Detects whether the line ends in the prompt control bytes (`0x7F 0x31`) to decide between a "press Enter to close" balloon and a timed, auto-closing one. A trailing auto-prompt (`0x7F 0x34 0x01`) closes the balloon instead of displaying.
3. `process_balloon` extracts the speaker name from the `Name : ` prefix, then runs text through `SubCharactersPreShift` (raw Shift-JIS byte substitutions to `[BL_*]` placeholders), `windower.from_shift_jis`, `SubCharactersPostShift` (placeholders to Unicode), color-code to `[BL_cN]` placeholders, `ui:wrap_text`, and finally placeholders to Windower `\cs(r,g,b)`/`\cr` markup using the active theme colours.
4. Returns a modified log line: untouched in DisplayMode 2, blanked in DisplayMode 1.

Balloons close on Enter, on leaving a conversation or zoning (packets `0x52`/`0x0B`), on a countdown for promptless lines, and optionally on player movement. Scroll Lock toggles visibility. Dragging the balloon background saves its centre to settings.

**`theme.lua`** has one function, `theme.apply`, which translates the raw `theme.xml` table (loaded via Windower `config`, so keys are lowercased: `textoffsetx`, `fontenglish`, ...) into a normalised `options` table with snake_case keys and fallbacks (System falls back to Dialogue; Timer falls back to Prompt position + Message font). Any new theme setting must be plumbed through here.

**`ui.lua`** owns the Windower `images`/`texts` primitives and all layout math. `ui:position()` recomputes every element from the message background's position, theme offsets, and `Scale`; it is called after any change in scale, portrait presence, or prompt animation. `ui:set_character(name)` resolves portraits and per-character balloon backgrounds. `ui:set_type(mode)` swaps dialogue vs system styling. Text reveal animation and prompt bounce run from the `prerender` event via `animate_text_display`/`animate_prompt`.

## Themes and portraits

- A theme is `themes/<name>/theme.xml` plus PNGs with fixed names: `balloon.png`, `system.png`, `name-bg.png`, `advance-prompt.png`, and optionally `portrait-bg.png`/`portrait-frame.png`. Image paths are hard-coded in `theme.lua`; only the XML sections `<Portrait>`, `<Prompt>`, `<Timer>`, `<System>`, and `<Stroke>` are optional.
- Do not put XML comments in `theme.xml`; they break Windower's config loader (see commit b07a725).
- `<MaxLength>` (and `<Portrait><MaxLength>`) is a strict character count per wrapped line; wrapping is by character count, not pixel width, so it must be tuned per font.
- Portrait lookup order in `ui:set_character`: `themes/<theme>/portraits/<Name> (S).png` and `portraits/<Name> (S).png` when the zone name ends in `[S]` (Wings of the Goddess past zones), then `themes/<theme>/portraits/<Name>.png`, then `portraits/<Name>.png`. Filenames must match the in-game NPC name exactly, including spaces and hyphens.
- Portraits in `portraits/` are 256x256 transparent PNGs. `docs/Portrait-Creation.md` describes the AltanaView + ImageMagick workflow. `.bmp`, `.kra`, and `*.png~` intermediates are gitignored.
- Per-NPC balloon backgrounds go in `themes/<theme>/characters/<Name>.png`.

## Conventions

- Bump `_addon.version` in `Balloon.lua` and add an entry to the English changelog in `readme.txt` when shipping a user-visible change.
- `defaults.lua` holds user setting defaults; Windower persists them to `data/settings.xml` (gitignored). Theme-level values belong in `theme.xml`, not `defaults.lua`.
- Element symbols and colour codes are mapped to `[BL_*]` placeholders before Shift-JIS conversion specifically so they survive the conversion and wrapping; keep that ordering when adding new substitutions. Element symbol bytes are `0xEF` followed by `0x1F`..`0x26`; `$` (Water, `0x24`) and `%` (Light, `0x25`) are `%`-escaped in the Lua patterns.
