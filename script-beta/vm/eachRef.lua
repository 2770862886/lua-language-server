local guide   = require 'parser.guide'
local files   = require 'files'
local vm      = require 'vm.vm'
local library = require 'library'
local await   = require 'await'

local function ofCall(func, index, callback, offset)
    offset = offset or 0
    vm.eachRef(func, function (info)
        local src = info.source
        local returns
        if src.type == 'main' or src.type == 'function' then
            returns = src.returns
        end
        if returns then
            -- 搜索函数第 index 个返回值
            for _, rtn in ipairs(returns) do
                local val = rtn[index-offset]
                if val then
                    callback {
                        source   = val,
                        mode     = 'return',
                    }
                    vm.eachRef(val, callback)
                end
            end
        end
    end)
end

local function ofCallSelect(call, index, callback)
    local slc = call.parent
    if slc.index == index then
        vm.eachRef(slc.parent, callback)
        return
    end
    if call.extParent then
        for i = 1, #call.extParent do
            slc = call.extParent[i]
            if slc.index == index then
                vm.eachRef(slc.parent, callback)
                return
            end
        end
    end
end

local function ofSpecialCall(call, func, index, callback, offset)
    local name = func.special
    offset = offset or 0
    if name == 'setmetatable' then
        if index == 1 + offset then
            local args = call.args
            if args[1+offset] then
                vm.eachRef(args[1+offset], callback)
            end
            if args[2+offset] then
                vm.eachField(args[2+offset], function (info)
                    if info.key == 's|__index' then
                        vm.eachRef(info.source, callback)
                        if info.value then
                            vm.eachRef(info.value, callback)
                        end
                    end
                end)
            end
            vm.setMeta(args[1+offset], args[2+offset])
        end
    elseif name == 'require' then
        if index == 1 + offset then
            local result = vm.getLinkUris(call)
            if result then
                local myUri = guide.getRoot(call).uri
                for _, uri in ipairs(result) do
                    if not files.eq(uri, myUri) then
                        local ast = files.getAst(uri)
                        if ast then
                            ofCall(ast.ast, 1, callback)
                        end
                    end
                end
            end

            local args = call.args
            if args[1+offset] then
                if args[1+offset].type == 'string' then
                    local objName = args[1+offset][1]
                    local lib = library.library[objName]
                    if lib then
                        callback {
                            source   = lib,
                            mode     = 'value',
                        }
                    end
                end
            end
        end
    elseif name == 'pcall'
    or     name == 'xpcall' then
        if index >= 2-offset then
            local args = call.args
            if args[1+offset] then
                vm.eachRef(args[1+offset], function (info)
                    local src = info.source
                    if src.type == 'function' then
                        ofCall(src, index, callback, 1+offset)
                        ofSpecialCall(call, src, index, callback, 1+offset)
                    end
                end)
            end
        end
    end
end

local function asSetValue(value, callback)
    if value.type == 'field'
    or value.type == 'method' then
        value = value.parent
    end
    local parent = value.parent
    if not parent then
        return
    end
    if parent.type == 'local'
    or parent.type == 'setglobal'
    or parent.type == 'setlocal'
    or parent.type == 'setfield'
    or parent.type == 'setmethod'
    or parent.type == 'setindex'
    or parent.type == 'tablefield'
    or parent.type == 'tableindex' then
        if parent.value == value then
            vm.eachRef(parent, callback)
            if guide.getName(parent) == '__index' then
                if parent.type == 'tablefield'
                or parent.type == 'tableindex' then
                    local t = parent.parent
                    local args = t.parent
                    if args[2] == t then
                        local call = args.parent
                        local func = call.node
                        if func.special == 'setmetatable' then
                            vm.eachRef(args[1], callback)
                        end
                    end
                end
            end
        end
    end
end

local function ofSelect(source, callback)
    -- 检查函数返回值
    local call = source.vararg
    if call.type == 'call' then
        ofCall(call.node, source.index, callback)
        ofSpecialCall(call, call.node, source.index, callback)
    end
end

local function ofSelf(loc, callback)
    -- self 的2个特殊引用位置：
    -- 1. 当前方法定义时的对象（mt）
    local method = loc.method
    local node   = method.node
    vm.eachRef(node, callback)
    -- 2. 调用该方法时传入的对象
end

local function getCallRecvs(call)
    local parent = call.parent
    if parent.type ~= 'select' then
        return nil
    end
    local extParent = call.extParent
    local recvs = {}
    recvs[1] = parent.parent
    if extParent then
        for _, p in ipairs(extParent) do
            recvs[#recvs+1] = p.parent
        end
    end
    return recvs
end

--- 自己作为函数的参数
local function asArg(source, callback)
    local parent = source.parent
    if not parent then
        return
    end
    if parent.type == 'callargs' then
        local call = parent.parent
        local func = call.node
        local name = func.special
        if name == 'setmetatable' then
            if parent[1] == source then
                if parent[2] then
                    vm.eachField(parent[2], function (info)
                        if info.key == 's|__index' then
                            vm.eachRef(info.source, callback)
                            if info.value then
                                vm.eachRef(info.value, callback)
                            end
                        end
                    end)
                end
                local recvs = getCallRecvs(call)
                if recvs and recvs[1] then
                    vm.eachRef(recvs[1], callback)
                end
                vm.setMeta(source, parent[2])
            end
        end
    end
end

--- 自己作为函数的返回值
local function asReturn(source, callback)
    local parent = source.parent
    if source.type == 'field'
    or source.type == 'method' then
        parent = parent.parent
    end
    if not parent or parent.type ~= 'return' then
        return
    end
    local func = guide.getParentFunction(source)
    if func.type == 'main' then
        local myUri = func.uri
        local uris = files.findLinkTo(myUri)
        if not uris then
            return
        end
        for _, uri in ipairs(uris) do
            local ast = files.getAst(uri)
            if ast then
                local links = vm.getLinks(ast.ast)
                if links then
                    for linkUri, calls in pairs(links) do
                        if files.eq(linkUri, myUri) then
                            for i = 1, #calls do
                                ofCallSelect(calls[i], 1, callback)
                            end
                        end
                    end
                end
            end
        end
    else
        local index
        for i = 1, #parent do
            if parent[i] == source then
                index = i
                break
            end
        end
        if not index then
            return
        end
        vm.eachRef(func, function (info)
            local src = info.source
            local call = src.parent
            if not call or call.type ~= 'call' then
                return
            end
            local recvs = getCallRecvs(call)
            if recvs and recvs[index] then
                vm.eachRef(recvs[index], callback)
            elseif index == 1 then
                callback {
                    type   = 'call',
                    source = call,
                }
            end
        end)
    end
end

local function ofLocal(loc, callback)
    -- 方法中的 self 使用了一个虚拟的定义位置
    if loc.tag ~= 'self' then
        callback {
            source   = loc,
            mode     = 'declare',
        }
    end
    if loc.ref then
        for _, ref in ipairs(loc.ref) do
            if ref.type == 'getlocal' then
                callback {
                    source   = ref,
                    mode     = 'get',
                }
                vm.eachRef(ref, callback)
            elseif ref.type == 'setlocal' then
                callback {
                    source   = ref,
                    mode     = 'set',
                }
                vm.eachRef(ref, callback)
                if ref.value then
                    vm.eachRef(ref.value, callback)
                end
            end
        end
    end
    if loc.tag == 'self' then
        ofSelf(loc, callback)
    end
    if loc.value then
        vm.eachRef(loc.value, callback)
    end
    if loc.tag == '_ENV' and loc.ref then
        for _, ref in ipairs(loc.ref) do
            if ref.type == 'getlocal' then
                local parent = ref.parent
                if parent.type == 'getfield'
                or parent.type == 'getindex' then
                    if guide.getKeyName(parent) == '_G' then
                        callback {
                            source   = parent,
                            mode     = 'get',
                        }
                    end
                end
            elseif ref.type == 'getglobal' then
                if guide.getName(ref) == '_G' then
                    callback {
                        source   = ref,
                        mode     = 'get',
                    }
                end
            end
        end
    end
end

local function ofGlobal(source, callback)
    local key = guide.getKeyName(source)
    local node = source.node
    if node.tag == '_ENV' then
        local uris = files.findGlobals(key)
        for _, uri in ipairs(uris) do
            local ast = files.getAst(uri)
            local globals = vm.getGlobals(ast.ast)
            if globals and globals[key] then
                for _, info in ipairs(globals[key]) do
                    callback(info)
                    if info.value then
                        vm.eachRef(info.value, callback)
                    end
                end
            end
        end
    else
        vm.eachField(node, function (info)
            if key == info.key then
                callback {
                    source   = info.source,
                    mode     = info.mode,
                }
                if info.value then
                    vm.eachRef(info.value, callback)
                end
            end
        end)
    end
end

local function ofField(source, callback)
    if not source then
        return
    end
    local parent = source.parent
    local key    = guide.getKeyName(source)
    if parent.type == 'tablefield'
    or parent.type == 'tableindex' then
        local tbl = parent.parent
        vm.eachField(tbl, function (info)
            if key == info.key then
                callback {
                    source   = info.source,
                    mode     = info.mode,
                }
                vm.eachRef(info.source, callback)
                if info.value then
                    vm.eachRef(info.value, callback)
                end
            end
        end)
    else
        local node = parent.node
        vm.eachField(node, function (info)
            if key == info.key then
                callback {
                    source   = info.source,
                    mode     = info.mode,
                }
                vm.eachRef(info.source, callback)
                if info.value then
                    vm.eachRef(info.value, callback)
                end
            end
        end)
    end
end

local function ofLiteral(source, callback)
    local parent = source.parent
    if not parent then
        return
    end
    if parent.type == 'setindex'
    or parent.type == 'getindex'
    or parent.type == 'tableindex' then
        ofField(source, callback)
    end
end

local function ofLabel(source, callback)
    callback {
        source = source,
        mode   = 'set',
    }
    if source.ref then
        for _, ref in ipairs(source.ref) do
            callback {
                source = ref,
                mode   = 'get',
            }
        end
    end
end

local function ofGoTo(source, callback)
    local name = source[1]
    local label = guide.getLabel(source, name)
    if label then
        ofLabel(label, callback)
    end
end

local function ofMain(source, callback)
    callback {
        source = source,
        mode   = 'main',
    }
end

local function asParen(source, callback)
    if source.parent and source.parent.type == 'paren' then
        vm.eachRef(source.parent, callback)
    end
end

local function ofSelfValue(source, callback)
    callback {
        source   = source,
        mode     = 'value',
    }
end

local function eachRef(source, callback)
    local stype = source.type
    if     stype == 'local' then
        ofLocal(source, callback)
    elseif stype == 'getlocal'
    or     stype == 'setlocal' then
        ofLocal(source.node, callback)
    elseif stype == 'setglobal'
    or     stype == 'getglobal' then
        ofGlobal(source, callback)
    elseif stype == 'field'
    or     stype == 'method' then
        ofField(source, callback)
    elseif stype == 'setfield'
    or     stype == 'getfield'
    or     stype == 'tablefield' then
        ofField(source.field, callback)
    elseif stype == 'setmethod'
    or     stype == 'getmethod' then
        ofField(source.method, callback)
    elseif stype == 'number'
    or     stype == 'boolean'
    or     stype == 'string' then
        ofLiteral(source, callback)
        ofSelfValue(source, callback)
    elseif stype == 'goto' then
        ofGoTo(source, callback)
    elseif stype == 'label' then
        ofLabel(source, callback)
    elseif stype == 'table'
    or     stype == 'function' then
        ofSelfValue(source, callback)
    elseif stype == 'select' then
        ofSelect(source, callback)
    elseif stype == 'call' then
        ofCall(source.node, 1, callback)
        ofSpecialCall(source, source.node, 1, callback)
    elseif stype == 'main' then
        ofMain(source, callback)
    elseif stype == 'paren' then
        eachRef(source.exp, callback)
    end
    asArg(source, callback)
    asReturn(source, callback)
    asParen(source, callback)
    asSetValue(source, callback)
end

--- 判断2个对象是否拥有相同的引用
function vm.isSameRef(a, b)
    local cache = vm.cache.eachRef[a]
    if cache then
        -- 相同引用的source共享同一份cache
        return cache == vm.cache.eachRef[b]
    else
        return vm.eachRef(a, function (info)
            if info.source == b then
                return true
            end
        end) or false
    end
end

local function applyCache(cache, callback, max)
    await.delay(function ()
        return files.globalVersion
    end)
    if max then
        if max > #cache then
            max = #cache
        end
    else
        max = #cache
    end
    for i = 1, max do
        local res = callback(cache[i])
        if res ~= nil then
            return res
        end
    end
end

local function eachRef(source, callback)
    local list   = { source }
    local mark = {}
    local result = {}
    local state  = {}
    local function found(src, mode)
        local info
        if src.mode then
            info = src
            src = info.source
        end
        if not mark[src] then
            list[#list+1] = src
        end
        if info then
            mark[src] = info
        elseif mode then
            mark[src] = {
                source = src,
                mode   = mode,
            }
        end
    end
    while #list > 0 do
        local max = #list
        local src = list[max]
        list[max] = nil
        vm.refOf(state, src, found)
    end
    for _, info in pairs(mark) do
        result[#result+1] = info
    end
    return result
end

--- 获取所有的引用
function vm.eachRef(source, callback, max)
    local cache = vm.cache.eachRef[source]
    if cache then
        applyCache(cache, callback, max)
        return
    end
    local unlock = vm.lock('eachRef', source)
    if not unlock then
        return
    end
    cache = eachRef(source, callback)
    unlock()
    for i = 1, #cache do
        local src = cache[i].source
        vm.cache.eachRef[src] = cache
    end
    applyCache(cache, callback, max)
end
