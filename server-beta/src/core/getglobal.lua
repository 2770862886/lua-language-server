local guide    = require 'parser.guide'

local m = {}

function m:def(source, callback)
    -- _ENV
    local key = guide.getKeyName(source)
    self:eachField(source.node, key, function (src, mode)
        if mode == 'set' then
            callback(src, mode)
        end
    end)
    self:eachSpecial(function (name, src)
        if name == '_G' then
            local parent = src.parent
            if guide.getKeyName(parent) == key then
                self:childDef(parent, callback)
            end
        elseif name == 'rawset' then
            local t, k = self:callArgOf(src.parent)
            if self:getSpecialName(t) == '_G'
            and guide.getKeyName(k) == key then
                callback(src.parent, 'set')
            end
        end
    end)
end

function m:ref(source, callback)
    -- _ENV
    local key = guide.getKeyName(source)
    self:eachField(source.node, key, function (src, mode)
        if mode == 'set' or mode == 'get' then
            callback(src, mode)
        end
    end)
    self:eachSpecial(function (name, src)
        if name == '_G' then
            local parent = src.parent
            if guide.getKeyName(parent) == key then
                self:childRef(parent, callback)
            end
        elseif name == 'rawset' then
            local t, k = self:callArgOf(src.parent)
            if self:getSpecialName(t) == '_G'
            and guide.getKeyName(k) == key then
                callback(src.parent, 'set')
            end
        elseif name == 'rawget' then
            local t, k = self:callArgOf(src.parent)
            if self:getSpecialName(t) == '_G'
            and guide.getKeyName(k) == key then
                callback(src.parent, 'get')
            end
        end
    end)
end

function m:field(source, key, callback)
    local global = guide.getKeyName(source)
    local used = {}
    self:eachField(source.node, global, function (src, mode)
        if mode == 'get' then
            used[src] = true
            local parent = src.parent
            if key == guide.getKeyName(parent) then
                self:childRef(parent, callback)
            end
        end
    end)
    self:eachSpecial(function (name, src)
        if name == 'setmetatable' then
            local t, mt = self:callArgOf(src.parent)
            if used[t] then
                self:eachField(mt, 's|__index', function (src, mode)
                    if mode == 'set' then
                        self:eachValue(src, function (src)
                            self:eachField(src, key, callback)
                        end)
                    end
                end)
            end
        end
    end)
end

function m:value(source, callback)
    callback(source)
end

return m
