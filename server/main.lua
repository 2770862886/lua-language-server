local currentPath = debug.getinfo(1, 'S').source:sub(2)
local rootPath = currentPath:gsub('[^/\\]-$', '')
dofile('./' .. rootPath .. 'platform.lua')
local fs = require 'bee.filesystem'
ROOT = fs.absolute(fs.path(rootPath)):parent_path():parent_path()
LANG = LANG or 'en-US'

print(package.cpath)

--collectgarbage('generational')
collectgarbage("setpause", 100)
collectgarbage("setstepmul", 1000)

log = require 'log'
log.init(ROOT, ROOT / 'log' / 'service.log')
log.info('Lua Lsp startup, root: ', ROOT)
log.debug('ROOT:', ROOT:string())
ac = {}

--xpcall(dofile, log.debug, rootPath .. 'debugger.lua')
require 'utility'
require 'global_protect'
local service = require 'service'
local session = service()

session:listen()
