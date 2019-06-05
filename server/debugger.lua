local fs = require 'bee.filesystem'
local extensionPath = fs.path(os.getenv 'USERPROFILE') / '.vscode' / 'extensions'
log.debug('Search extensions at:', extensionPath:string())
if not fs.is_directory(extensionPath) then
    log.debug('Extension path is not a directory.')
    return
end

local luaDebugs = {}
for path in extensionPath:list_directory() do
    if fs.is_directory(path) then
        local name = path:filename():string()
        if name:find('actboy168.lua-debug-', 1, true) then
            luaDebugs[#luaDebugs+1] = name
        end
    end
end

if #luaDebugs == 0 then
    log.debug('Cant find "actboy168.lua-debug"')
    return
end

local function getVer(filename)
    local a, b, c = filename:match('(%d+)%.(%d+)%.(%d+)$')
    if not a then
        return 0
    end
    return a * 1000000 + b * 1000 + c
end

table.sort(luaDebugs, function (a, b)
    return getVer(a) > getVer(b)
end)

local debugPath = extensionPath / luaDebugs[1]
local cpath = "/runtime/win64/lua54/?.dll"
local path  = "/script/?.lua"

local function tryDebugger()
    local remote = package.searchpath('remotedebug', debugPath:string() .. cpath)
    local entry = package.searchpath('start_debug', debugPath:string() .. path)
    local rdebug = package.loadlib(remote,'luaopen_remotedebug')()
    local root = debugPath:string()
    local port = '11411'
    local addr = "127.0.0.1:" .. port
    local dbg = loadfile(entry)(rdebug, root, path, cpath)
    debug.getregistry()["lua-debug"] = dbg
    dbg:start(addr, true)
    log.debug('Debugger startup, listen port:', port)
    log.debug('Debugger args:', addr, root, path, cpath)
end

xpcall(tryDebugger, log.debug)
