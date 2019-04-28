local listMgr = require 'vm.list'

---@class EmmyReturn
local mt = {}
mt.__index = mt
mt.type = 'emmy.return'

function mt:getSource()
    return listMgr.get(self.source)
end

function mt:bindType(type)
    if type then
        self._bindType = type
    else
        return self._bindType
    end
end

return function (manager, source)
    local self = setmetatable({
        source = source.id,
        _manager = manager,
    }, mt)
    return self
end
