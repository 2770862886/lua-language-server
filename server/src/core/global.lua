local mt = {}
mt.__index = mt

function mt:clearGlobal(uri)
    self.get[uri] = nil
    self.set[uri] = nil
end

function mt:markSet(uri, k, v)
    local sets = self.set[uri]
    if not sets then
        sets = {}
        self.set[uri] = sets
    end
    sets[k] = v
end

function mt:markGet(uri, k)
    local gets = self.get[uri]
    if not gets then
        gets = {}
        self.get[uri] = gets
    end
    gets[k] = true
end

function mt:compileVM(uri, vm)
    self:clearGlobal(uri)
    for k, v in next, vm.env.child do
        local get, set
        for _, info in ipairs(v) do
            if info.type == 'get' then
                get = true
            elseif info.type == 'set' then
                set = true
            end
        end
        if set then
            self:markSet(uri, k, v)
        elseif get then
            self:markGet(uri, k)
        end
    end
end

function mt:getGlobal(key)
    for _, sets in pairs(self.set) do
        local v = sets[key]
        if v ~= nil then
            return v
        end
    end
    return nil
end

return function ()
    return setmetatable({
        get = {},
        set = {},
    }, mt)
end
