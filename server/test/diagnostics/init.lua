local core = require 'core'
local buildVM = require 'vm'
local parser  = require 'parser'
local service = require 'service'

rawset(_G, 'TEST', true)

local function catch_target(script)
    local list = {}
    local cur = 1
    local cut = 0
    while true do
        local start, finish  = script:find('<!.-!>', cur)
        if not start then
            break
        end
        list[#list+1] = { start - cut, finish - 4 - cut }
        cur = finish + 1
        cut = cut + 4
    end
    local new_script = script:gsub('<!(.-)!>', '%1')
    return new_script, list
end

local function founded(targets, results)
    if #targets ~= #results then
        return false
    end
    for _, target in ipairs(targets) do
        for _, result in ipairs(results) do
            if target[1] == result[1] and target[2] == result[2] then
                goto NEXT
            end
        end
        do return false end
        ::NEXT::
    end
    return true
end

function TEST(script)
    local new_script, target = catch_target(script)
    local lsp = service()
    local ast = parser:ast(new_script, 'lua', 'Lua 5.3')
    assert(ast)
    local lines = parser:lines(new_script)
    local vm = buildVM(ast, lsp)
    assert(vm)
    local datas = core.diagnostics(vm, lines, 'test')
    local results = {}
    for i, data in ipairs(datas) do
        results[i] = { data.start, data.finish }
    end

    if results[1] then
        if not founded(target, results) then
            error(('%s\n%s'):format(table.dump(target), table.dump(results)))
        end
    else
        assert(#target == 0)
    end
end

TEST [[
local <!x!>
]]

TEST [[
print(<!x!>)
print(<!log!>)
print(<!X!>)
print(<!Log!>)
print(_VERSION)
print(<!y!>)
print(Z)
Z = 1
]]

TEST [[
::<!LABEL!>::
]]

TEST [[
<!    !>
]]

TEST [[
X = 1<!  !>
]]

TEST [[
X = [=[  
    ]=]
]]

TEST [[
local x
print(x)
local <!x!>
print(x)
]]

TEST [[
local x
print(x)
local <!x!>
print(x)
local <!x!>
print(x)
]]

TEST [[
local _
print(_)
local _
print(_)
local _ENV
<!print!>(_ENV) -- 由于重定义了_ENV，因此print变为了未定义全局变量
]]

TEST [[
print(1)
_ENV = nil
]]

TEST [[
print()
<!('string')!>:sub(1, 1)
]]

TEST [[
print()
('string')
]]

TEST [[
local function x(a, b)
    return a, b
end
x(1, 2, <!3!>)
]]

TEST [[
InstanceName = 1
Instance = _G[InstanceName]
]]

TEST [[
(''):sub(1, 2)
]]


TEST [=[
return [[   
   
]]
]=]

TEST [[
local mt, x
function mt:m()
    function x:m()
    end
end
]]

TEST [[
local mt = {}
function mt:f()
end
]]

TEST [[
local function f(<!self!>)
end
f()
]]

TEST [[
local function f(var)
    print(var)
end
local var
f(var)
]]

TEST [[
local function f(a, b)
    return a, b
end
f(1, 2, <!3!>, <!4!>)
]]

TEST [[
local mt = {}
function mt:f(a, b)
    return a, b
end
mt.f(1, 2, 3, <!4!>)
]]


TEST [[
local mt = {}
function mt.f(a, b)
    return a, b
end
mt:f(1, <!2!>, <!3!>, <!4!>)
]]

TEST [[
local mt = {}
function mt:f(a, b)
    return a, b
end
mt:f(1, 2, <!3!>, <!4!>)
]]

TEST [[
local function f(a, b, ...)
    return a, b
end
f(1, 2, 3, 4)
]]

TEST [[
next({}, 1, <!2!>)
print(1, 2, 3, 4, 5)
]]

--TEST [[
--local realTostring = tostring
--tostring = function () end
--tostring(<!1!>)
--tostring = realTostring
--tostring(1)
--]]

TEST [[
<!aa!> = 1
tostring = 1
ROOT = 1
_G.bb = 1
]]

TEST [[
local f = load('')
f(1, 2, 3)
]]

require 'config' .config.runtime.version = 'Lua 5.3'
TEST [[
<!warn!>(1)
]]

TEST [[
X = table[<!x!>]
]]

TEST [[
return {
    x = 1,
    y = 2,
    <!x!> = 3,
}
]]

TEST [[
local m = {}
function m.open()
end

m:open()
]]

TEST [[
<!if true then
end!>
]]

TEST [[
<!if true then
else
end!>
]]

TEST [[
if true then
else
    return
end
]]

TEST [[
<!while true do
end!>
]]

TEST [[
<!for _ = 1, 10 do
end!>
]]

TEST [[
<!for _ in pairs(_VERSION) do
end!>
]]

TEST [[
local _ = 1, <!2!>
]]

TEST [[
_ = 1, <!2!>
]]

TEST [[
local function x()
    do
        local k
        print(k)
        x()
    end
    local k = 1
    print(k)
end
]]

TEST [[
local function x()
    local loc
    x()
    print(loc)
end
]]

TEST [[
---@class <!Class!>
---@class <!Class!>
]]

TEST [[
---@class A : <!B!>
]]

TEST [[
---@class <!A : B!>
---@class <!B : C!>
---@class <!C : D!>
---@class <!D : A!>
]]

TEST [[
---@class A : B
---@class B : C
---@class C : D
---@class D
]]

TEST [[
---@type <!A!>
]]

TEST [[
---@class A
---@type A|<!B!>|<!C!>
]]
