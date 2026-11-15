std = 'luajit'
-- Windower's addon environment: _addon/_libs/windower are injected by the
-- host, the rest come from require('luau') and the texts/images/chat libs.
globals = {
    '_addon', '_libs', 'windower', 'S', 'L', 'T', 'config', 'log', 'notice',
    'texts', 'images', 'res', 'chars',
    -- luau extends the standard libraries too
    string = {fields = {'trim', 'endswith', 'startswith', 'split'}},
    coroutine = {fields = {'sleep', 'close'}},
}
-- Balloon.lua defines its handlers as top-level globals (initialize, close, ...).
allow_defined_top = true
unused_args = false
-- the original code has some very long lines; don't fight it
max_line_length = false
files['test'] = {globals = {'package'}}
