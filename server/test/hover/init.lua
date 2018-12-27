local parser = require 'parser'
local matcher = require 'matcher'

rawset(_G, 'TEST', true)

function TEST(script)
    return function (expect)
        local start  = script:find('<?', 1, true)
        local finish = script:find('?>', 1, true)
        local pos = (start + finish) // 2 + 1
        local new_script = script:gsub('<[!?]', '  '):gsub('[!?]>', '  ')
        local ast = parser:ast(new_script)
        local vm = matcher.vm(ast)
        assert(vm)
        local result, source = matcher.findResult(vm, pos)
        local hover = matcher.hover(result, source)
        if expect then
            assert(hover)
            expect = expect:gsub('^[\r\n]*(.-)[\r\n]*$', '%1'):gsub('\r\n', '\n')
            local label = hover.label:gsub('^[\r\n]*(.-)[\r\n]*$', '%1'):gsub('\r\n', '\n')
            assert(expect == label)
        else
            assert(hover == nil)
        end
    end
end

TEST [[
local function <?x?>(a, b)
end
]]
"function x(a: any, b: any)"

TEST [[
local function x(a, b)
end
<?x?>()
]]
"function x(a: any, b: any)"

TEST [[
local mt = {}
mt.__index = mt

function mt:init(a, b, c)
    return {}
end

local obj = setmetatable({}, mt)

obj:<?init?>(1, '测试')
]]
[[
function mt:init(a: number, b: string, c: any)
  -> table
]]

TEST [[
local mt = {}
mt.__index = mt

function mt:init(a, b, c)
    return {}
end

local obj = setmetatable({}, mt)

obj:init(1, '测试')
obj.<?init?>(obj, 1, '测试')
]]
[[
function mt.init(self: table, a: number, b: string, c: any)
  -> table
]]

TEST [[
function obj.xxx()
end

obj.<?xxx?>()
]]
"function obj.xxx()"

TEST [[
obj.<?xxx?>()
]]
"function obj.xxx()"

TEST [[
local <?x?> = 1
]]
"local x: number = 1"

TEST [[
<?x?> = 1
]]
"global x: number = 1"

TEST [[
local t = {}
t.<?x?> = 1
]]
"field t.x: number = 1"

TEST [[
t = {}
t.<?x?> = 1
]]
"field t.x: number = 1"

TEST [[
local mt = {}
mt.__name = 'class'

local <?obj?> = setmetatable({}, mt)
]]
"local obj: *class"

TEST [[
local mt = {}
mt.name = 'class'
mt.__index = mt

local <?obj?> = setmetatable({}, mt)
]]
"local obj: *class"

TEST [[
local mt = {}
mt.TYPE = 'class'
mt.__index = mt

local <?obj?> = setmetatable({}, mt)
]]
"local obj: *class"

TEST [[
local mt = {}
mt.Class = 'class'
mt.__index = mt

local <?obj?> = setmetatable({}, mt)
]]
"local obj: *class"

TEST[[
local fs = require 'bee.filesystem'
local <?root?> = fs.current_path()
]]
"local root: *bee::filesystem"

TEST[[
('xx'):<?yy?>()
]]
"function *string:yy()"

TEST [[
local <?v?> = collectgarbage()
]]
"local v: any"

TEST [[
local type
w2l:get_default()[<?type?>]
]]
"local type: any"

TEST [[
<?load?>()
]]
[=[
function load(chunk: string/function [, chunkname: string [, mode: string [, env: table]]])
  -> function, error_message: string
]=]

TEST [[
string.<?lower?>()
]]
[[
function string.lower(string)
  -> string
]]

TEST [[
local function x(a, ...)
end

<?x?>(1, 2, 3, 4, 5, 6, 7)
]]
[[
function x(a: number, ...)
]]

TEST [[
local function x()
    return y()
end

<?x?>()
]]
[[
function x()
  -> any
]]

TEST [[
local mt = {}
mt.__index = mt

function mt:add(a, b)
end

local function init()
    return setmetatable({}, mt)
end

local t = init()
t:<?add?>()
]]
[[
function mt:add(a: any, b: any)
]]

TEST [[
local <?t?> = - 1000
]]
[[local t: number = -1000]]

TEST [[
for <?c?> in io.lines() do
end
]]
[[local c: string]]

TEST [[
local function f()
    return ...
end
local <?n?> = f()
]]
[[local n: any]]

TEST [[
local <?n?> = table.unpack(t)
]]
[[local n: any]]

TEST [[
local <?n?>
table.pack(n)
]]
[[
local n: any
]]

TEST [[
(<?'xxx'?>):sub()
]]
(nil)

TEST [[
local <?t?> = {
    a = 1,
    b = 2,
    c = 3,
}
]]
[[
local t: {
    a: number = 1,
    b: number = 2,
    c: number = 3,
}
]]

TEST [[
local <?t?> = {
    a = 1,
    [1] = 2,
    [true] = 3,
    [5.5] = 4,
    [{}] = 5,
    [function () end] = 6,
}
]]
[[
local t: {
    a: number = 1,
    [1]: number = 2,
    [true]: number = 3,
    [5.5]: number = 4,
    [*table]: number = 5,
    [*function]: number = 6,
}
]]
