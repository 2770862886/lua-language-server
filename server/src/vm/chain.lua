local valueMgr = require 'vm.value'
local sourceMgr = require 'vm.source'

local mt = {}
mt.__index = mt
mt.type = 'chain'

mt.min = 100
mt.max = 100
mt.count = 0

function mt:clearCache()
    if self.count <= self.max then
        return
    end
    local n = 0
    for uri, value in pairs(self.cache) do
        local ok = value:eachInfo(function ()
            return true
        end)
        if ok then
            n = n + 1
        else
            self.cache[uri] = nil
        end
    end
    self.count = n
    self.max = self.count * 2
    if self.max < self.min then
        self.max = self.min
    end
end

function mt:get(uri)
    if not self.cache[uri] then
        self.count = self.count + 1
        self:clearCache()
        self.cache[uri] = valueMgr.create('any', sourceMgr.dummy())
        self.cache[uri]:markGlobal()
        self.cache[uri].uri = uri
    end
    return self.cache[uri]
end

return function ()
    return setmetatable({
        cache = {},
    }, mt)
end