local guide  = require 'parser.guide'
local config = require 'config'

local type         = type
local setmetatable = setmetatable
local ipairs       = ipairs

_ENV = nil

---@class engineer
local mt = {}
mt.__index = mt
mt.type = 'engineer'

mt['local'] = function (self, source, mode, callback)
    if mode == 'def' then
        if source.tag ~= 'self' then
            callback(source, 'local')
        end
        if source.ref then
            for _, ref in ipairs(source.ref) do
                if ref.type == 'setlocal' then
                    callback(ref, 'set')
                end
            end
        end
        if source.tag == 'self' then
            local method = source.method
            local node = method.node
            self:search(node, node.type, mode, callback)
        end
    elseif mode == 'ref' then
        if source.tag ~= 'self' then
            callback(source, 'local')
        end
        if source.ref then
            for _, ref in ipairs(source.ref) do
                if ref.type == 'setlocal' then
                    callback(ref, 'set')
                elseif ref.type == 'getlocal' then
                    callback(ref, 'get')
                end
            end
        end
        if source.tag == 'self' then
            local method = source.method
            local node = method.node
            self:search(node, node.type, mode, callback)
        end
    elseif mode == 'field' then
        if source.ref then
            for _, ref in ipairs(source.ref) do
                if ref.type == 'getlocal' then
                    local parent = ref.parent
                    local tp     = parent.type
                    if tp == 'setfield'
                    or tp == 'getfield'
                    or tp == 'setindex'
                    or tp == 'getindex' then
                        callback(parent)
                    end
                end
            end
        end
    end
end
mt['getlocal'] = function (self, source, mode, callback)
    self:search(source.loc, 'local', mode, callback)
end
mt['setlocal'] = mt['getlocal']
mt['_G'] = function (self, source, mode, callback)
    if mode == 'def' then
        local parent = source.parent
        if parent.type == 'setfield'
        or parent.type == 'setindex' then
            callback(parent, 'set')
        elseif parent.type == 'getfield'
        or     parent.type == 'getindex' then
            self:search(parent, 'special', mode, callback)
        elseif parent.type == 'callargs' then
            self:search(parent.parent, 'special', mode, callback)
        end
    elseif mode == 'ref' then
        local parent = source.parent
        if parent.type == 'setfield'
        or parent.type == 'setindex' then
            callback(parent, 'set')
        elseif parent.type == 'getfield'
        or     parent.type == 'getindex' then
            callback(parent, 'get')
        elseif parent.type == 'getfield' then
            self:search(parent, 'special', mode, callback)
        elseif parent.type == 'callargs' then
            self:search(parent.parent, 'special', mode, callback)
        end
    end
end
mt['getglobal'] = function (self, source, mode, callback)
    local env = source.node
    if mode == 'def' then
        if env.ref then
            for _, ref in ipairs(env.ref) do
                if ref.type == 'setglobal' then
                    callback(ref, 'set')
                elseif ref.type == 'getglobal' then
                    self:search(ref, 'special', mode, callback)
                elseif ref.type == 'getlocal' then
                    self:search(ref, '_G', mode, callback)
                end
            end
        end
    elseif mode == 'ref' then
        if env.ref then
            for _, ref in ipairs(env.ref) do
                if ref.type == 'setglobal' then
                    callback(ref, 'set')
                elseif ref.type == 'getglobal' then
                    callback(ref, 'get')
                    self:search(ref, 'special', mode, callback)
                elseif ref.type == 'getlocal' then
                    self:search(ref, '_G', mode, callback)
                end
            end
        end
    elseif mode == 'field' then
        self:search(source, 'getglobal', 'ref', function (src)
            local parent = src.parent
            local tp     = parent.type
            if tp == 'setfield'
            or tp == 'getfield'
            or tp == 'setindex'
            or tp == 'getindex' then
                callback(parent)
            end
        end)
    end
end
mt['setglobal'] = mt['getglobal']
mt['field'] = function (self, source, mode, callback)
    local node = source.parent.node
    local key = guide.getKeyName(source)
    self:eachRef(node, 'field', function (src)
        if key == guide.getKeyName(src) then
            if mode == 'def' then
                if src.type == 'setfield' then
                    callback(src.field, 'set')
                end
            end
        end
    end)
end
mt['special'] = function (self, source, mode, callback)
    local name = self:getSpecial(source)
    if not name then
        return
    end
    if mode == 'def' then
        if name == 's|_G' then
            self:search(source, '_G', mode, callback)
        elseif name == 's|rawset' then
            callback(source.parent, 'set')
        end
    end
end
mt['asindex'] = function (self, source, mode, callback)
    local parent = source.parent
    if not parent then
        return
    end
    if parent.type ~= 'setindex' and parent.type ~= 'getindex' then
        return
    end
    local node = parent.node
    local key = guide.getKeyName(source)
    self:eachRef(node, 'field', function (src)
        if key == guide.getKeyName(src) then
            if mode == 'def' then
                if src.type == 'setfield' then
                    callback(src.field, 'set')
                elseif src.type == 'setindex' then
                    callback(src.index, 'set')
                end
            end
        end
    end)
end
mt['number']  = mt['asindex']
mt['boolean'] = mt['asindex']
mt['string'] = function (self, source, mode, callback)
    mt['asindex'](self, source, mode, callback)
end

function mt:getSpecial(source)
    local node = source.node
    if node.tag ~= '_ENV' then
        return nil
    end
    local name = guide.getKeyName(source)
    return name
end

function mt:search(source, method, mode, callback)
    local f = mt[method]
    if not f then
        return
    end
    f(self, source, mode, callback)
end

function mt:eachRef(source, mode, callback)
    local tp = source.type
    self:search(source, tp, mode, callback)
end

return function (ast)
    local self = setmetatable({
        step = 0,
        ast  = ast.ast,
    }, mt)
    if not ast.vm then
        ast.vm = {}
    end
    return self
end
