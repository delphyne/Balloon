-- Tests for Balloon's text pipeline, run outside the game:
--   luajit test/test_Balloon.lua        (from the addon directory)
-- Windower's globals and libs (luau, texts, images, config, chat.chars,
-- resources) are stubbed. themes/default/theme.xml is parsed for real so
-- theme.lua runs against the shipped theme.

package.path = './?.lua;' .. package.path

local chat = {}
local handlers = {}
local existing_files = {}
local info = {logged_in = true, language = 'English', zone = 1, chat_open = false}

-------------------------------------------------------------------------------
-- luau stubs

S = function(t) local s = {} for _, v in ipairs(t) do s[v] = true end return s end
L = function(t)
    return setmetatable(t, {__index = {
        empty = function(self) return #self == 0 end,
        concat = function(self, sep) return table.concat(self, sep) end,
    }})
end
function string.endswith(s, suffix) return s:sub(-#suffix) == suffix end
function string.trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end
function string.split(s, sep)
    local out = {}
    for part in (s .. sep):gmatch('(.-)' .. sep:gsub('%p', '%%%0')) do out[#out + 1] = part end
    return out
end
string.gfind = string.gfind or string.gmatch
coroutine.sleep = function() end
-- luau gives functions a metatable so fn:schedule(delay) works; here it is a no-op
debug.setmetatable(function() end, {__index = {schedule = function() end}})
log = function(line) chat[#chat + 1] = line end

-------------------------------------------------------------------------------
-- windower stubs

_addon = {}
windower = {
    addon_path = './',
    get_windower_settings = function() return {ui_x_res = 1920, ui_y_res = 1080} end,
    register_event = function(name, fn) handlers[name] = fn end,
    add_to_chat = function(_, line) chat[#chat + 1] = line end,
    from_shift_jis = function(s) return s end,
    to_shift_jis = function(s) return s end,
    file_exists = function(path) return existing_files[path] == true end,
    ffxi = {
        get_info = function() return info end,
        get_player = function() return {id = 1} end,
    },
}

-- A minimal XML reader good enough for theme.xml: nested elements, no
-- attributes, leaf text. Keys are lowercased and numeric leaves converted,
-- which is what Windower's config library does.
local function parse_xml(xml)
    local pos = 1
    local function parse_children()
        local node = {}
        while true do
            local s, e, tag = xml:find('<(%w+)>', pos)
            local close_s = xml:find('</', pos)
            if not s or (close_s and close_s < s) then return node end
            pos = e + 1
            local inner_s, inner_e, text = xml:find('^%s*([^<]-)%s*</' .. tag .. '>', pos)
            if inner_s then
                node[tag:lower()] = tonumber(text) or text
                pos = inner_e + 1
            else
                node[tag:lower()] = parse_children()
                local _, ce = xml:find('</' .. tag .. '>', pos)
                pos = ce + 1
            end
        end
    end
    return parse_children()
end

local function read_file(path)
    local f = assert(io.open(path, 'rb'), 'cannot open ' .. path)
    local s = f:read('*a')
    f:close()
    return s
end

-- luau exposes config as a global
package.preload['luau'] = function() config = require('config') end
package.preload['config'] = function()
    return {
        load = function(path, defaults)
            if type(path) == 'table' then
                local t = {}
                for k, v in pairs(path) do t[k] = v end
                return t
            end
            local xml = read_file(path)
            local t = parse_xml(xml).settings.global
            for k, v in pairs(defaults) do t[k] = v end
            return t
        end,
        save = function() end,
    }
end
package.preload['chat.chars'] = function()
    return {
        bstar = string.char(0x81, 0x99),
        wstar = string.char(0x81, 0x9A),
        wave = string.char(0x81, 0x60),
        note = string.char(0x81, 0xED),
        sharp = string.char(0x81, 0xEB),
        flat = string.char(0x81, 0xEC),
    }
end

-- texts/images objects record what was set on them; every other method is a no-op.
local function widget()
    local w = {_v = {}}
    return setmetatable(w, {__index = function(_, k)
        if k == 'pos' then return function(self, x, y) self._v.x, self._v.y = x, y end end
        if k == 'pos_x' then return function(self) return self._v.x or 0 end end
        if k == 'pos_y' then return function(self) return self._v.y or 0 end end
        if k == 'size' then return function(self, a, b) self._v.w, self._v.h = a, b end end
        if k == 'width' then return function(self) return self._v.w or 0 end end
        if k == 'height' then return function(self) return self._v.h or 0 end end
        if k == 'show' then return function(self) self._v.visible = true end end
        if k == 'hide' then return function(self) self._v.visible = false end end
        return function(self, ...)
            if select('#', ...) > 0 then self._v[k] = ... else return self._v[k] end
        end
    end})
end
package.preload['texts'] = function() return {new = widget} end

-- The native gamepad module (native/balloonpad.c) is stubbed: set
-- pad_stub.pressed to an XInput button mask and the next poll reports it.
local pad_stub = {pressed = 0}
package.preload['balloonpad'] = function()
    return {
        poll = function()
            local pressed = pad_stub.pressed
            pad_stub.pressed = 0
            return true, pressed, pressed, 0, 0
        end,
    }
end
package.preload['images'] = function() return {new = widget} end
res = {zones = {
    [1] = {en = 'Southern San d\'Oria'},
    [2] = {en = 'Southern San d\'Oria [S]'},
}}

-------------------------------------------------------------------------------

dofile('Balloon.lua')
handlers['load']()
-- Balloon.lua keeps its state local; the ui module is shared through require.
local ui = require('ui')

local incoming_text = assert(handlers['incoming text'], 'no incoming text handler')
local command = assert(handlers['addon command'], 'no addon command handler')

local PROMPT = string.char(0x7F, 0x31)
local AUTO_PROMPT = string.char(0x7F, 0x34, 0x01)
local NEWLINE = string.char(0x07)

local failures = 0
local function check(name, got, want)
    if got == want then
        print('ok   ' .. name)
    else
        failures = failures + 1
        print('FAIL ' .. name)
        print('  wanted: ' .. tostring(want))
        print('  got:    ' .. tostring(got))
    end
end

-- The addon shows the whole message at once after enough prerender frames.
local function shown_text()
    for _ = 1, 100 do handlers['prerender']() end
    return ui.message_text:text()
end

-------------------------------------------------------------------------------
-- speaker and prompt detection

command('2')
chat = {}

local line = 'Iroha : Welcome, traveler.' .. PROMPT
check('mode 2 passes the log line through', incoming_text(line, line, 150, 150, false), line)
check('speaker name extracted', ui.name_text:text(), ' Iroha')
check('prompt stripped and name removed', shown_text(), '\n Welcome, traveler.')
check('balloon is open', ui:hidden(), false)
check('prompt indicator shown', ui.prompt._v.visible, true)
check('countdown hidden', ui.timer_text._v.visible, false)

line = 'Iroha : Something stirs in the distance.'
incoming_text(line, line, 144, 144, false)
check('countdown shown', ui.timer_text._v.visible, true)
check('countdown starts at NoPromptCloseDelay', ui.timer_text:text(), '10')

incoming_text(AUTO_PROMPT, AUTO_PROMPT, 150, 150, false)
check('auto-prompt line closes the balloon', ui:hidden(), true)

line = 'You hear something moving to the east...'
incoming_text(line .. PROMPT, line .. PROMPT, 151, 151, false)
check('system text has no speaker', ui.name_text:text(), ' ')
check('system text uses the system background', ui.message_background:path(), './themes/default/system.png')
check('name background hidden without a speaker', ui.name_background._v.visible, false)

line = 'Iroha : Hello.' .. PROMPT
incoming_text(line, line, 150, 150, false)
check('dialogue uses the balloon background', ui.message_background:path(), './themes/default/balloon.png')

check('unrelated chat modes are ignored', incoming_text('Hello', 'Hello', 1, 1, false), nil)

-------------------------------------------------------------------------------
-- display modes

command('1')
line = 'Iroha : Hidden from the log.' .. PROMPT
check('mode 1 blanks a named line to its prompt bytes', incoming_text(line, line, 150, 150, false), PROMPT)
line = 'No speaker here.' .. PROMPT
check('mode 1 blanks an unnamed line', incoming_text(line, line, 150, 150, false), '\n')

command('0')
line = 'Iroha : Balloons off.' .. PROMPT
check('mode 0 leaves the log alone', incoming_text(line, line, 150, 150, false), line)
command('2')

-------------------------------------------------------------------------------
-- text substitutions

line = 'Iroha : Bring me ' .. string.char(0x1E, 0x03) .. 'the key' .. string.char(0x1E, 0x01) .. ' now.' .. PROMPT
incoming_text(line, line, 150, 150, false)
check('key item colour code becomes theme colour', shown_text(),
    '\n Bring me \\cs(97,127,217)the key\\cr now.')

-- Water is 0xEF 0x24; the 0x25 in Balloon.lua's pattern is a '%' escape for the '$'.
line = 'Iroha : ' .. string.char(0xEF, 0x1F) .. ' and ' .. string.char(0xEF, 0x24) .. PROMPT
incoming_text(line, line, 150, 150, false)
check('element symbols become coloured words', shown_text(),
    '\n \\cs(255,0,0)Fire \\cr and \\cs(0,76,153)Water \\cr')

line = 'Iroha : La la' .. string.char(0x81, 0xF4) .. ' ' .. string.char(0x81, 0x99) .. PROMPT
incoming_text(line, line, 150, 150, false)
check('shift-jis symbols become unicode', shown_text(), '\n La la♪ ☆')

-- the game sends its own codes for musical symbols, which are not valid shift-jis
line = 'Iroha : La la' .. string.char(0x81, 0xED) .. ' ' .. string.char(0x81, 0xEB) .. string.char(0x81, 0xEC) .. PROMPT
incoming_text(line, line, 150, 150, false)
check('game musical symbol codes become unicode', shown_text(), '\n La la♪ ♯♭')

line = 'Iroha : First line.' .. NEWLINE .. 'Second line.' .. PROMPT
incoming_text(line, line, 150, 150, false)
check('0x07 splits lines', shown_text(), '\n First line.\n Second line.')

line = 'Iroha : Wait...what?' .. PROMPT
incoming_text(line, line, 150, 150, false)
check('ellipsis gets a breaking space', shown_text(), '\n Wait... what?')

-------------------------------------------------------------------------------
-- word wrapping

local max = ui._theme_options.message.max_length
local words = {}
for i = 1, 60 do words[i] = ('word%02d'):format(i) end
local wrapped = ui:wrap_text(table.concat(words, ' '))
local longest, count = 0, 0
for l in (wrapped .. '\n'):gmatch('(.-)\n') do
    count = count + 1
    if #l > longest then longest = #l end
end
check('wrapped lines never exceed MaxLength', longest <= max, true)
check('wrapping produced several lines', count > 1, true)
check('no word is split', wrapped:gsub('%s', ''), table.concat(words))

-------------------------------------------------------------------------------
-- portraits

existing_files['./portraits/Iroha.png'] = true
existing_files['./portraits/Iroha (S).png'] = true
existing_files['./themes/default/portraits/Lion.png'] = true

line = 'Iroha : Present day.' .. PROMPT
incoming_text(line, line, 150, 150, false)
check('portrait found in the shared folder', ui.portrait:path(), './portraits/Iroha.png')
check('portrait shown', ui.portrait._v.visible, true)
check('portrait layout narrows the text', ui._has_portrait and ui._theme_options.portrait.max_length < max, true)

info.zone = 2
incoming_text(line, line, 150, 150, false)
check('[S] zone prefers the (S) portrait', ui.portrait:path(), './portraits/Iroha (S).png')
info.zone = 1

line = 'Lion : Theme folder first.' .. PROMPT
incoming_text(line, line, 150, 150, false)
check('theme portrait folder wins over the shared one', ui.portrait:path(), './themes/default/portraits/Lion.png')

line = 'Nobody : No picture.' .. PROMPT
incoming_text(line, line, 150, 150, false)
check('missing portrait hides the frame', ui.portrait._v.visible, false)

command('portrait')
line = 'Iroha : Portraits off.' .. PROMPT
incoming_text(line, line, 150, 150, false)
check('//bl portrait toggles portraits off', ui.portrait._v.visible, false)
command('portrait')

-------------------------------------------------------------------------------
-- gamepad

line = 'Iroha : Press to continue.' .. PROMPT
incoming_text(line, line, 150, 150, false)
check('prompt shown before any pad input', ui.prompt._v.visible, true)
pad_stub.pressed = 0x0010 -- Start
handlers['prerender']()
check('non-face button leaves the prompt alone', ui.prompt._v.visible, true)
pad_stub.pressed = 0x1000 -- A
handlers['prerender']()
check('face button hides the prompt', ui.prompt._v.visible, false)
check('face button keeps the balloon open', ui:hidden(), false)
check('face button keeps the text', ui.message_text:text(), '\n Press to continue.')

line = 'Iroha : Next line.' .. PROMPT
incoming_text(line, line, 150, 150, false)
check('next prompted line shows the prompt again', ui.prompt._v.visible, true)

line = 'Iroha : No prompt here.'
incoming_text(line, line, 144, 144, false)
pad_stub.pressed = 0x1000
handlers['prerender']()
check('face button leaves a timed balloon open', ui:hidden(), false)
check('timed balloon keeps its countdown', ui.timer_text._v.visible, true)

-------------------------------------------------------------------------------
-- commands

chat = {}
command('test', 'Tester', ':', 'A', 'test', 'balloon.')
check('//bl test shows a balloon', ui:hidden(), false)
check('//bl test sets the speaker', ui.name_text:text(), ' Tester')
check('//bl test text', shown_text(), '\n A test balloon.')

chat = {}
command('theme', 'nope')
check('unknown theme is reported', chat[1], 'theme.xml not found under themes/nope/theme.xml')

chat = {}
command('scale', '1.5')
check('scale is reported', chat[1], 'scale changed from 1.00 to 1.50')
check('scale resizes the balloon', ui.message_background:width(), ui._theme_options.message.width * 1.5)
command('scale', '1')

handlers['keyboard'](28, true, 0, false)
check('Enter closes the balloon', ui:hidden(), true)
handlers['keyboard'](28, false, 0, false)

-------------------------------------------------------------------------------

if failures > 0 then
    print(failures .. ' failure(s)')
    os.exit(1)
end
print('all tests passed')
