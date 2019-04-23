local findSource = require 'core.find_source'
local Mode

local function parseValueSimily(callback, vm, source)
    local key = source[1]
    if not key then
        return nil
    end
    vm:eachSource(function (other)
        if other == source then
            goto CONTINUE
        end
        if      other[1] == key
            and not other:bindLocal()
            and other:bindValue()
            and source:bindValue() ~= other:bindValue()
        then
            if Mode == 'definition' then
                if other:action() == 'set' then
                    callback(other)
                end
            elseif Mode == 'reference' then
                if other:action() == 'set' or other:action() == 'get' then
                    callback(other)
                end
            end
        end
        :: CONTINUE ::
    end)
end

local function parseLocal(callback, vm, source)
    ---@type Local
    local loc = source:bindLocal()
    callback(loc:getSource())
    loc:eachInfo(function (info, src)
        if Mode == 'definition' then
            if info.type == 'set' or info.type == 'local' then
                if vm.uri == src:getUri() then
                    if source.id >= src.id then
                        callback(src)
                    end
                else
                    callback(src)
                end
            end
        elseif Mode == 'reference' then
            if info.type == 'set' or info.type == 'local' or info.type == 'return' or info.type == 'get' then
                callback(src)
            end
        end
    end)
end

local function parseValueByValue(callback, vm, source, value)
    value:eachInfo(function (info, src)
        if Mode == 'definition' then
            if info.type == 'set' or info.type == 'local' then
                if vm.uri == src:getUri() then
                    if source.id >= src.id then
                        callback(src)
                    end
                else
                    callback(src)
                end
            end
            if info.type == 'return' then
                if src.type == 'function'
                or (src.type == 'simple' and src[#src].type == 'call')
                then
                    callback(src)
                end
            end
        elseif Mode == 'reference' then
            if info.type == 'set' or info.type == 'local' or info.type == 'return' or info.type == 'get' then
                callback(src)
            end
        end
    end)
end

local function parseValue(callback, vm, source)
    local value = source:bindValue()
    local isGlobal
    if value then
        isGlobal = value:isGlobal()
        parseValueByValue(callback, vm, source, value)
        local emmy = value:getEmmy()
        if emmy and emmy.type == 'emmy.type' then
            ---@type EmmyType
            local emmyType = emmy
            emmyType:eachClass(function (class)
                if class and class:getValue() then
                    parseValueByValue(callback, vm, class:getValue():getSource(), class:getValue())
                end
            end)
        end
    end
    local parent = source:get 'parent'
    for _ = 1, 3 do
        if parent then
            local ok = parent:eachInfo(function (info, src)
                if Mode == 'definition' then
                    if info.type == 'set child' and info[1] == source[1] then
                        callback(src)
                        return true
                    end
                elseif Mode == 'reference' then
                    if (info.type == 'set child' or info.type == 'get child') and info[1] == source[1] then
                        callback(src)
                        return true
                    end
                end
            end)
            if ok then
                break
            end
            parent = parent:getMetaMethod('__index')
        end
    end
    return isGlobal
end

local function parseLabel(callback, vm, label)
    label:eachInfo(function (info, src)
        if Mode == 'definition' then
            if info.type == 'set' then
                callback(src)
            end
        elseif Mode == 'reference' then
            if info.type == 'set' or info.type == 'get' then
                callback(src)
            end
        end
    end)
end

local function jumpUri(callback, vm, source)
    local uri = source:get 'target uri'
    callback {
        start = 0,
        finish = 0,
        uri = uri
    }
end

local function parseClass(callback, vm, source)
    local className = source:get 'target class'
    vm.emmyMgr:eachClass(className, function (class)
        if Mode == 'definition' then
            if class.type == 'emmy.class' then
                local src = class:getSource()
                callback(src)
            end
        elseif Mode == 'reference' then
            if class.type == 'emmy.class' or class.type == 'emmy.typeUnit' then
                local src = class:getSource()
                callback(src)
            end
        end
    end)
end

local function parseFunction(callback, vm, source)
    if Mode == 'definition' then
        callback(source:bindFunction():getSource())
        source:bindFunction():eachInfo(function (info, src)
            if info.type == 'set' or info.type == 'local' then
                if vm.uri == src:getUri() then
                    if source.id >= src.id then
                        callback(src)
                    end
                else
                    callback(src)
                end
            end
        end)
    elseif Mode == 'reference' then
        callback(source:bindFunction():getSource())
        source:bindFunction():eachInfo(function (info, src)
            if info.type == 'set' or info.type == 'local' or info.type == 'get' then
                callback(src)
            end
        end)
    end
end

local function makeList(source)
    local list = {}
    local mark = {}
    return list, function (src)
        if Mode == 'definition' then
            if source == src then
                return
            end
        end
        if mark[src] then
            return
        end
        mark[src] = true
        local uri = src.uri
        if uri == '' then
            uri = nil
        end
        list[#list+1] = {
            src.start,
            src.finish,
            src.uri
        }
    end
end

return function (vm, pos, mode)
    local source = findSource(vm, pos)
    if not source then
        return nil
    end
    Mode = mode
    local list, callback = makeList(source)
    local isGlobal
    if source:bindLocal() then
        parseLocal(callback, vm, source)
    end
    if source:bindValue() then
        isGlobal = parseValue(callback, vm, source)
    end
    if source:bindLabel() then
        parseLabel(callback, vm, source:bindLabel())
    end
    if source:bindFunction() then
        parseFunction(callback, vm, source)
    end
    if source:get 'target uri' then
        jumpUri(callback, vm, source)
    end
    if source:get 'in index' then
        isGlobal = parseValue(callback, vm, source)
    end
    if source:get 'target class' then
        parseClass(callback, vm, source)
    end

    if #list == 0 then
        parseValueSimily(callback, vm, source)
    end

    return list, isGlobal
end
