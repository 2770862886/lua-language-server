local createMulti = require 'vm.multi'
local createValue = require 'vm.value'
local createLocal = require 'vm.local'

local mt = {}
mt.__index = mt
mt.type = 'function'
mt._runed = 0
mt._top = 0

function mt:getUri()
    return self.source.uri
end

function mt:push(source)
    self._top = self._top + 1
    self.locals[self._top] = {}
    self.blocks[self._top] = source
end

function mt:pop()
    local closedBlock = self.blocks[self._top]
    local closedLocals = self.locals[self._top]
    for _, loc in pairs(closedLocals) do
        loc:close(closedBlock.finish)
    end
    self._top = self._top - 1
end

function mt:saveLocal(name, loc)
    if loc.type ~= 'local' then
        error('saveLocal必须是local')
    end
    local old = self:loadLocal(name)
    if old then
        loc:shadow(old)
    end
    self.locals[self._top][name] = loc
end

function mt:loadLocal(name)
    for i = self._top, 1, -1 do
        local locals = self.locals[i]
        local loc = locals[name]
        if loc then
            return loc
        end
    end
    return nil
end

function mt:eachLocal(callback)
    local mark = {}
    for i = self._top, 1, -1 do
        local locals = self.locals[i]
        for name, loc in pairs(locals) do
            if not mark[name] then
                mark[name] = true
                local res = callback(name, loc)
                if res ~= nil then
                    return res
                end
            end
        end
    end
    return nil
end

function mt:saveLabel(label)
    if not self._label then
        self._label = {}
    end
    self._label[#self._label+1] = label
end

function mt:loadLabel(name)
    if not self._label then
        return nil
    end
    for _, label in ipairs(self._label) do
        if label:getName() == name then
            return label
        end
    end
    return nil
end

function mt:setReturn(index, value)
    self:set('hasReturn', true)
    if not self.returns then
        self.returns = createMulti()
    end
    if value then
        self.returns[index] = value
    else
        self.returns[index] = createValue('any', self.source)
    end
end

function mt:getReturn(index)
    if self.maxReturns and index and self.maxReturns < index then
        return createValue('nil')
    end
    if not self.returns then
        self.returns = createMulti()
    end
    if index then
        return self.returns:get(index) or createValue('nil')
    else
        return self.returns
    end
end

function mt:returnDots(index)
    if not self.returns then
        self.returns = createMulti()
    end
    self.returns[index] = createMulti()
end

function mt:loadDots()
    if not self._dots then
        self._dots = createMulti()
    end
    return self._dots
end

function mt:setObject(value, source)
    self._objectValue = value
    self._objectSource = source
end

function mt:getObject()
    return self._objectValue, self._objectSource
end

function mt:hasRuned()
    return self._runed > 0
end

function mt:run()
    self._runed = self._runed + 1
    if not self.source then
        return
    end

    if self._runed > 1 then
        --return
    end

    -- 第一次运行函数时，创建函数的参数
    if self._runed ~= 1 then
        return
    end

    -- 如果是面向对象形式的函数，创建隐藏的参数self
    if self._objectSource then
        local loc = createLocal('self', self._objectSource, self._objectValue)
        self:saveLocal('self', loc)
    end

    -- 显性声明的参数
    self:createArgs()
end

function mt:setArgs(values)
    for i = 1, #self.argValues do
        self.argValues[i] = nil
    end
    for i = 1, #values do
        self.argValues[i] = values[i]
    end
end

function mt:createArg(arg, values)
    if arg.type == 'name' then
        local value = table.remove(values, 1) or createValue('nil', arg)
        local loc = createLocal(arg[1], arg, value)
        self:saveLocal(arg[1], loc)
        self.args[#self.args+1] = loc
    elseif arg.type == '...' then
        self._dots = createMulti()
        for i = 1, #values do
            self._dots:set(i, values[i])
        end
    end
end

function mt:createLibArg(arg)
    if arg.type == '...' then
        self._dots = createMulti()
    else
        local name = arg.name or '_'
        local loc = createLocal(name, nil, createValue('any'))
        self:saveLocal(name, loc)
        self.args[#self.args+1] = loc
    end
end

function mt:hasDots()
    return self._dots ~= nil
end

function mt:createArgs()
    if not self.source then
        return
    end
    local args = self.source.arg
    if not args then
        return
    end
    local values = {}
    for i, value in ipairs(self.argValues) do
        values[i] = value
    end
    if args.type == 'list' then
        for _, arg in ipairs(args) do
            self:createArg(arg, values)
        end
    else
        self:createArg(args, values)
    end
end

function mt:set(name, v)
    if not self._flag then
        self._flag = {}
    end
    self._flag[name] = v
end

function mt:get(name)
    if not self._flag then
        return nil
    end
    return self._flag[name]
end

return function (source)
    local self = setmetatable({
        source = source,
        locals = {},
        blocks = {},
        args = {},
        argValues = {},
    }, mt)
    self:push(source)
    return self
end
