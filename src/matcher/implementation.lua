local parser = require 'parser'

local pos
local defs = {}
local scopes
local result
local namePos
local colonPos

local DUMMY_TABLE = {}

local function scopeInit()
    scopes = {{}}
end

local function scopeGet(name)
    for i = #scopes, 1, -1 do
        local scope = scopes[i]
        local obj = scope[name]
        if obj then
            return obj
        end
    end
    return nil
end

local function scopeSet(obj)
    local name = obj[1]
    local scope = scopes[#scopes]
    scope[name] = obj
end

local function globalSet(obj)
    local name = obj[1]
    for i = #scopes, 1, -1 do
        local scope = scopes[i]
        local old = scope[name]
        if old then
            scope[name] = obj
            return
        end
    end
    local scope = scopes[1]
    scope[name] = obj
end

local function scopePush()
    scopes[#scopes+1] = {}
end

local function scopePop()
    scopes[#scopes] = nil
end

local function checkImplementation(name, p)
    if pos < p or pos > p + #name then
        return
    end
    result = scopeGet(name)
end

function defs.NamePos(p)
    namePos = p
end

function defs.Name(str)
    checkImplementation(str, namePos)
    return {str, namePos, type = 'name'}
end

function defs.DOTSPos(p)
    namePos = p
end

function defs.DOTS(str)
    checkImplementation(str, namePos)
    return {str, namePos, type = 'name'}
end

function defs.COLONPos(p)
    colonPos = p
end

function defs.ColonName(name)
    name.colon = colonPos
    return name
end

function defs.LocalVar(names)
    for _, name in ipairs(names) do
        scopeSet(name)
    end
end

function defs.LocalSet(names)
    for _, name in ipairs(names) do
        scopeSet(name)
    end
end

function defs.Set(simples)
    for _, simple in ipairs(simples) do
        if simple.type == 'simple' and #simple == 1 then
            local obj = simple[1]
            local name = obj[1]
            globalSet(obj)
        end
    end
end

function defs.Simple(...)
    return { type = 'simple', ... }
end

function defs.ArgList(...)
    if ... == '' then
        return DUMMY_TABLE
    end
    return { type = 'list', ... }
end

function defs.FuncName(...)
    if ... == '' then
        return DUMMY_TABLE
    end
    return { type = 'simple', ... }
end

function defs.FunctionDef(simple, args)
    if #simple == 1 then
        globalSet(simple[1])
    end
    scopePush()
    -- 判断隐藏的局部变量self
    if #simple > 0 then
        local name = simple[#simple]
        if name.colon then
            scopeSet {'self', name.colon, name.colon, type = 'name'}
        end
    end
    for _, arg in ipairs(args) do
        if arg.type == 'simple' and #arg == 1 then
            local name = arg[1]
            scopeSet(name)
        end
        if arg.type == 'name' then
            scopeSet(arg)
        end
    end
end

function defs.FunctionLoc(simple, args)
    if #simple == 1 then
        scopeSet(simple[1])
    end
    scopePush()
    -- 判断隐藏的局部变量self
    if #simple > 0 then
        local name = simple[#simple]
        if name.colon then
            scopeSet {'self', name.colon, name.colon, type = 'name'}
        end
    end
    for _, arg in ipairs(args) do
        if arg.type == 'simple' and #arg == 1 then
            local name = arg[1]
            scopeSet(name)
        end
        if arg.type == 'name' then
            scopeSet(arg)
        end
    end
end

function defs.Function()
    scopePop()
end

function defs.DoDef()
    scopePush()
end

function defs.Do()
    scopePop()
end

function defs.IfDef()
    scopePush()
end

function defs.If()
    scopePop()
end

function defs.ElseIfDef()
    scopePush()
end

function defs.ElseIf()
    scopePop()
end

function defs.ElseDef()
    scopePush()
end

function defs.Else()
    scopePop()
end

function defs.LoopDef(name)
    scopePush()
    scopeSet(name)
end

function defs.Loop()
    scopePop()
end

function defs.LoopStart(name, exp)
    return name
end

function defs.NameList(...)
    return { type = 'list', ... }
end

function defs.SimpleList(...)
    return { type = 'list', ... }
end

function defs.InDef(names)
    scopePush()
    for _, name in ipairs(names) do
        scopeSet(name)
    end
end

function defs.In()
    scopePop()
end

function defs.WhileDef()
    scopePush()
end

function defs.While()
    scopePop()
end

function defs.RepeatDef()
    scopePush()
end

function defs.Until()
    scopePop()
end

return function (buf, pos_)
    pos = pos_
    result = nil
    scopeInit()

    local suc, err = parser.grammar(buf, 'Lua', defs)
    if not suc then
        return false, '语法错误', err
    end

    if not result then
        return false, 'No word'
    end
    local name, start, finish = result[1], result[2], result[3]
    if not start then
        return false, 'No match'
    end
    if not finish then
        finish = start + #name - 1
    end
    return true, start, finish
end
