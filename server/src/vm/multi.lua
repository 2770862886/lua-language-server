local createValue = require 'vm.value'

local mt = {}
mt.__index = mt
mt.type = 'multi'

function mt:push(value, isLast)
    if value.type == 'list' then
        if isLast then
            for _, v in ipairs(value) do
                self[#self+1] = v
            end
        else
            self[#self+1] = value[1]
        end
    else
        self[#self+1] = value
    end
end

function mt:get(index)
    for n = #self+1, index do
        self[n] = createValue('any')
    end
    return self[index]
end

function mt:set(index, value)
    for n = #self+1, index-1 do
        self[n] = createValue('any')
    end
    self[index] = value
end

function mt:first()
    local value = self[1]
    if not value then
        return createValue('nil')
    end
    if value.type == 'multi' then
        return value:first()
    else
        return value
    end
end

function mt:eachValue(callback)
    local i = 0
    for n, value in ipairs(self) do
        if value.type == 'multi' then
            if n == #self then
                value:eachValue(function (_, nvalue)
                    i = i + 1
                    callback(i, nvalue)
                end)
            else
                i = i + 1
                value:first()
            end
        else
            i = i + 1
            callback(i, value)
        end
    end
end

function mt:merge(other)
    other:eachValue(function (_, value)
        self:push(value)
    end)
end

return function ()
    local self = setmetatable({}, mt)
    return self
end
