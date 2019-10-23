local guide        = require 'parser.guide'
local files        = require 'files'
local methods      = require 'searcher.methods'
local tableUnpack  = table.unpack
local error        = error
local setmetatable = setmetatable
local assert       = assert

_ENV = nil
local specials = {
    ['_G']           = true,
    ['rawset']       = true,
    ['rawget']       = true,
    ['setmetatable'] = true,
    ['require']      = true,
    ['dofile']       = true,
    ['loadfile']     = true,
}

---@class searcher_old
local mt = {}
mt.__index = mt
mt.__name = 'searcher'

--- 获取特殊对象的名字
function mt:getSpecialName(source)
    local spName = self.cache.specialName[source]
    if spName ~= nil then
        if spName then
            return spName
        end
        return nil
    end
    local function getName(info)
        local src = info.source
        if src.type == 'getglobal' then
            local node = src.node
            if node.tag ~= '_ENV' then
                return nil
            end
            local name = guide.getKeyName(src)
            if name:sub(1, 2) ~= 's|' then
                return nil
            end
            spName = name:sub(3)
            if not specials[spName] then
                spName = nil
            end
        elseif src.type == 'local' then
            if src.tag == '_ENV' then
                spName = '_G'
            end
        elseif src.type == 'getlocal' then
            local loc = src.loc
            if loc.tag == '_ENV' then
                spName = '_G'
            end
        end
    end
    self:eachValue(source, getName)
    self.cache.specialName[source] = spName or false
    return spName
end

--- 遍历特殊对象
---@param callback fun(name:string, source:table)
function mt:eachSpecial(callback)
    local cache = self.cache.special
    if cache then
        for i = 1, #cache do
            callback(cache[i][1], cache[i][2])
        end
        return
    end
    cache = {}
    self.cache.special = cache
    guide.eachSource(self.ast, function (source)
        if source.type == 'getlocal'
        or source.type == 'getglobal'
        or source.type == 'local'
        or source.type == 'field'
        or source.type == 'string' then
            local name = self:getSpecialName(source)
            if name then
                cache[#cache+1] = { name, source }
            end
        end
    end)
    for i = 1, #cache do
        callback(cache[i][1], cache[i][2])
    end
end

--- 遍历元素
---@param source table
---@param key string
---@param callback fun(info:table)
function mt:eachField(source, key, callback)
    local cache = self.cache.field[source]
    if cache and cache[key] then
        for i = 1, #cache[key] do
            callback(cache[key][i])
        end
        return
    end
    local tp = source.type
    local d = methods[tp]
    if not d then
        return
    end
    local f = d.eachField
    if not f then
        return
    end
    if self.step >= 100 then
        error('Stack overflow!')
        return
    end
    self.step = self.step + 1
    local mark = {}
    if not cache then
        cache = {}
        self.cache.field[source] = cache
    end
    cache[key] = {}
    f(self, source, key, function (info)
        local src = info.source
        local uri = info.uri
        assert(src and uri)
        if mark[src] then
            return
        end
        mark[src] = true
        info.searcher = files.getSearcher(uri)
        cache[key][#cache[key]+1] = info
    end)
    for i = 1, #cache[key] do
        callback(cache[key][i])
    end
    self.step = self.step - 1
end

--- 遍历引用
---@param source table
---@param callback fun(info:table)
function mt:eachRef(source, callback)
    local cache = self.cache.ref[source]
    if cache then
        for i = 1, #cache do
            callback(cache[i])
        end
        return
    end
    local tp = source.type
    local d = methods[tp]
    if not d then
        return
    end
    local f = d.eachRef
    if not f then
        return
    end
    if self.step >= 100 then
        error('Stack overflow!')
        return
    end
    self.step = self.step + 1
    cache = {}
    self.cache.ref[source] = cache
    local mark = {}
    f(self, source, function (info)
        local src = info.source
        local uri = info.uri
        assert(src and uri)
        if mark[src] then
            return
        end
        mark[src] = true
        info.searcher = files.getSearcher(uri)
        cache[#cache+1] = info
    end)
    for i = 1, #cache do
        callback(cache[i])
    end
    self.step = self.step - 1
end

--- 遍历定义
---@param source table
---@param callback fun(info:table)
function mt:eachDef(source, callback)
    local cache = self.cache.def[source]
    if cache then
        for i = 1, #cache do
            callback(cache[i])
        end
        return
    end
    local tp = source.type
    local d = methods[tp]
    if not d then
        return
    end
    local f = d.eachDef
    if not f then
        return
    end
    if self.step >= 100 then
        error('Stack overflow!')
        return
    end
    self.step = self.step + 1
    cache = {}
    self.cache.def[source] = cache
    local mark = {}
    f(self, source, function (info)
        local src = info.source
        local uri = info.uri
        assert(src and uri)
        if mark[src] then
            return
        end
        mark[src] = true
        info.searcher = files.getSearcher(uri)
        cache[#cache+1] = info
    end)
    for i = 1, #cache do
        callback(cache[i])
    end
    self.step = self.step - 1
end

--- 遍历value
---@param source table
---@param callback fun(info:table)
function mt:eachValue(source, callback)
    local cache = self.cache.value[source]
    if cache then
        for i = 1, #cache do
            callback(cache[i])
        end
        return
    end
    local tp = source.type
    local d = methods[tp]
    if not d then
        return
    end
    local f = d.eachValue
    if not f then
        return
    end
    if self.step >= 100 then
        error('Stack overflow!')
        return
    end
    self.step = self.step + 1
    cache = {}
    self.cache.value[source] = cache
    local mark = {}
    f(self, source, function (info)
        local src = info.source
        local uri = info.uri
        assert(src and uri)
        if mark[src] then
            return
        end
        mark[src] = true
        info.searcher = files.getSearcher(uri)
        cache[#cache+1] = info
    end)
    for i = 1, #cache do
        callback(cache[i])
    end
    self.step = self.step - 1
end

--- 获取value
---@param source table
---@return value table
function mt:getValue(source)
    local tp = source.type
    local d = methods[tp]
    if not d then
        return
    end
    local f = d.getValue
    if not f then
        return
    end
    if self.step >= 100 then
        error('Stack overflow!')
        return
    end
    self.step = self.step + 1
    local value = f(self, source)
    self.step = self.step - 1
    return value
end

--- 获取函数的参数
---@param source table
---@return table arg1
---@return table arg2
function mt:callArgOf(source)
    if not source or source.type ~= 'call' then
        return
    end
    local args = source.args
    if not args then
        return
    end
    return tableUnpack(args)
end

--- 获取调用函数的返回值
---@param source table
---@return table return1
---@return table return2
function mt:callReturnOf(source)
    if not source or source.type ~= 'call' then
        return
    end
    local parent = source.parent
    local extParent = source.extParent
    if extParent then
        local returns = {parent.parent}
        for i = 1, #extParent do
            returns[i+1] = extParent[i].parent
        end
        return tableUnpack(returns)
    elseif parent then
        return parent.parent
    end
end

--- 获取函数定义的返回值
---@param source table
---@param callback fun(source:table)
function mt:functionReturnOf(source, callback)
    if not source or source.type ~= 'function' then
        return
    end
    local returns = guide.getReturns(source)
    for i = 1, #returns do
        local src = returns[i]
        callback()
    end
end

--- 获取source的索引，模式与值
---@param source table
---@return table field
---@return string mode
---@return table value
function mt:childMode(source)
    if     source.type == 'getfield' then
        return source.field, 'get'
    elseif source.type == 'setfield' then
        return source.field, 'set', source.value
    elseif source.type == 'getmethod' then
        return source.method, 'get'
    elseif source.type == 'setmethod' then
        return source.method, 'set', source.value
    elseif source.type == 'getindex' then
        return source.index, 'get'
    elseif source.type == 'setindex' then
        return source.index, 'set', source.value
    elseif source.type == 'field' then
        return self:childMode(source.parent)
    elseif source.type == 'method' then
        return self:childMode(source.parent)
    end
    return nil, nil
end

---@class engineer_old
local m = {}

--- 新建搜索器
---@param uri string
---@return searcher_old
function m.create(uri)
    local ast = files.getAst(uri)
    local searcher = setmetatable({
        step = 0,
        ast  = ast.ast,
        uri  = uri,
        cache = {
            def   = {},
            ref   = {},
            field = {},
            value = {},
            specialName = {},
        },
    }, mt)
    return searcher
end

return m
