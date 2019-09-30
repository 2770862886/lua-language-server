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
        callback(source, 'local')
        if source.ref then
            for _, ref in ipairs(source.ref) do
                if ref.type == 'setlocal' then
                    callback(ref, 'set')
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
        if parent.type == 'setfield' then
            callback(parent, 'set')
        elseif parent.type == 'getfield' then
            self:search(parent, 'special', mode, callback)
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
    end
end
mt['setglobal'] = mt['getglobal']
mt['special'] = function (self, source, mode, callback)
    if mode == 'def' then
        local name = guide.getKeyName(source)
        if name == '_G' then
            self:search(source, '_G', mode, callback)
        end
    end
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
    if not ast.vm then
        ast.vm = {}
    end
    local self = setmetatable({
        step = 0,
        ast  = ast.ast,
    }, mt)
    return self
end
