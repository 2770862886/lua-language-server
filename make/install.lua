local fs = require 'bee.filesystem'
local sp = require 'bee.subprocess'

local CWD = fs.current_path()

local output = CWD / 'server' / 'bin'
local bindir = CWD / 'build' / 'msvc' / 'bin'
local beedir = CWD / '3rd' / 'bee.lua' / 'bin' / 'msvc_x86_release'

fs.create_directories(output)
fs.copy_file(bindir / 'lni.dll', output / 'lni.dll', true)
fs.copy_file(bindir / 'lpeglabel.dll', output / 'lpeglabel.dll', true)
fs.copy_file(beedir / 'bee.dll', output / 'bee.dll', true)
fs.copy_file(beedir / 'lua54.dll', output / 'lua54.dll', true)
fs.copy_file(beedir / 'lua.exe', output / 'lua-language-server.exe', true)


local process = assert(sp.spawn {
    bindir / 'rcedit.exe',
    output / 'lua-language-server.exe',
    '--set-icon',
    CWD / 'images' / 'icon.ico'
})
assert(process:wait())


local msvc_crt = dofile 'make/msvc_crt.lua'
msvc_crt('x86', output)
