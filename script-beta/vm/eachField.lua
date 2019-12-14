local guide   = require 'parser.guide'
local vm      = require 'vm.vm'
local files   = require 'files'
local await   = require 'await'
local library = require 'library'

local function ofTabel(value, callback)
    if value.library then
        if value.child then
            for k, field in pairs(value.child) do
                callback {
                    source   = field,
                    key      = 's|' .. k,
                    value    = field,
                    mode     = 'set',
                }
            end
        end
    else
        for _, field in ipairs(value) do
            if field.type == 'tablefield'
            or field.type == 'tableindex' then
                callback {
                    source   = field,
                    key      = guide.getKeyName(field),
                    value    = field.value,
                    mode     = 'set',
                }
            end
        end
    end
end

local function ofENV(source, callback)
    if source.type == 'getlocal' then
        local parent = source.parent
        if parent.type == 'getfield'
        or parent.type == 'getmethod'
        or parent.type == 'getindex' then
            callback {
                source   = parent,
                key      = guide.getKeyName(parent),
                mode     = 'get',
            }
        end
    elseif source.type == 'getglobal' then
        callback {
            source   = source,
            key      = guide.getKeyName(source),
            mode     = 'get',
        }
    elseif source.type == 'setglobal' then
        callback {
            source   = source,
            key      = guide.getKeyName(source),
            mode     = 'set',
            value    = source.value,
        }
    end
end

local function ofSpecialArg(source, callback)
    local args = source.parent
    local call = args.parent
    local func = call.node
    local name = func.special
    if    name == 'rawset' then
        if args[1] == source and args[2] then
            callback {
                source   = call,
                key      = guide.getKeyName(args[2]),
                value    = args[3],
                mode     = 'set',
            }
        end
    elseif name == 'rawget' then
        if args[1] == source and args[2] then
            callback {
                source   = call,
                key      = guide.getKeyName(args[2]),
                mode     = 'get',
            }
        end
    elseif name == 'setmetatable' then
        if args[1] == source and args[2] then
            vm.eachField(args[2], function (info)
                if info.key == 's|__index' and info.value then
                    vm.eachField(info.value, callback)
                end
            end)
        end
    end
end

local function ofVar(source, callback)
    local parent = source.parent
    if not parent then
        return
    end
    if parent.type == 'getfield'
    or parent.type == 'getmethod'
    or parent.type == 'getindex' then
        callback {
            source   = parent,
            key      = guide.getKeyName(parent),
            mode     = 'get',
        }
        return
    end
    if parent.type == 'setfield'
    or parent.type == 'setmethod'
    or parent.type == 'setindex' then
        callback {
            source   = parent,
            key      = guide.getKeyName(parent),
            value    = parent.value,
            mode     = 'set',
        }
        return
    end
    if parent.type == 'callargs' then
        ofSpecialArg(source, callback)
    end
end

local function eachField(source, callback)
    vm.eachRef(source, function (info)
        local src = info.source
        if src.tag == '_ENV' then
            if src.ref then
                for _, ref in ipairs(src.ref) do
                    ofENV(ref, callback)
                end
            end
            for name, lib in pairs(library.global) do
                callback {
                    source = lib,
                    key    = 's|' .. name,
                    mode   = 'value',
                }
            end
        elseif src.type == 'getlocal'
        or     src.type == 'getglobal'
        or     src.type == 'getfield'
        or     src.type == 'getmethod'
        or     src.type == 'getindex' then
            ofVar(src, callback)
        elseif src.type == 'field'
        or     src.type == 'method' then
            ofVar(src.parent, callback)
        elseif src.type == 'table' then
            ofTabel(src, callback)
        end
        local lib = library.object[src.type]
        if lib then
            for k, v in pairs(lib.child) do
                callback {
                    source = v,
                    key    = 's|' .. k,
                    mode   = 'value',
                }
            end
        end
    end)
end

--- 获取所有的field
function vm.eachField(source, callback)
    local cache = vm.cache.eachField[source]
    if cache then
        await.delay(function ()
            return files.globalVersion
        end)
        for i = 1, #cache do
            local res = callback(cache[i])
            if res ~= nil then
                return res
            end
        end
        return
    end
    local unlock = vm.lock('eachField', source)
    if not unlock then
        return
    end
    cache = {}
    vm.cache.eachField[source] = cache
    local mark = {}
    eachField(source, function (info)
        local src = info.source
        if mark[src] then
            return
        end
        mark[src] = true
        cache[#cache+1] = info
    end)
    unlock()
    vm.eachRef(source, function (info)
        local src = info.source
        vm.cache.eachField[src] = cache
    end)
    await.delay(function ()
        return files.globalVersion
    end)
    for i = 1, #cache do
        local res = callback(cache[i])
        if res ~= nil then
            return res
        end
    end
end
