local guide    = require 'parser.guide'
local checkSMT = require 'seacher.setmetatable'

local m = {}

function m:eachDef(source, callback)
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
                callback(parent, 'set')
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

function m:eachRef(source, callback)
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
                if parent.type:sub(1, 3) == 'set' then
                    callback(parent, 'set')
                else
                    callback(parent, 'get')
                end
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

function m:eachField(source, key, callback)
    local used = {}
    local found = false
    used[source] = true

    self:eachRef(source, function (src)
        used[src] = true
        local child, mode, value = self:childMode(src)
        if child then
            if key == guide.getKeyName(child) then
                callback(child, mode)
            end
            if value then
                self:eachField(value, key, callback)
            end
            return
        end
        if src.type == 'getglobal' then
            local parent = src.parent
            child, mode, value = self:childMode(parent)
            if child then
                if key == guide.getKeyName(child) then
                    callback(child, mode)
                end
                if value then
                    self:eachField(value, key, callback)
                end
            end
        elseif src.type == 'setglobal' then
            self:eachField(src.value, key, callback)
        else
            self:eachField(src, key, callback)
        end
    end)

    checkSMT(self, key, used, found, callback)
end

function m:eachValue(source, callback)
    callback(source)
    if source.value then
        self:eachValue(source.value, callback)
    end
end

return m
