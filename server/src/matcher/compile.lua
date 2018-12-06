local env = require 'matcher.env'
local mt = {}
mt.__index = mt

function mt:getVar(key, source)
    if key == nil then
        return nil
    end
    local var = self.env.var[key]
             or self:getField(self.env.var._ENV, key, source) -- 这里不需要用getVar来递归获取_ENV
    if not var then
        var = self:addField(self:getVar '_ENV', key, source)
    end
    if var and var.meta then
        var = var.meta
    end
    return var
end

function mt:addInfo(obj, type, source)
    if not obj then
        return nil
    end
    obj[#obj+1] = {
        type = type,
        source = source,
    }
    return obj
end

function mt:createVar(type, key, source)
    local var = {
        type = type,
        key = key,
        source = source,
        childs = {},
    }
    self.results.vars[#self.results.vars+1] = var
    return var
end

function mt:createLabel(key)
    local lbl = {
        key = key,
        type = 'label',
    }
    self.results.labels[#self.results.labels+1] = lbl
    return lbl
end

function mt:createDots()
    local dots = {
        type = 'dots',
    }
    self.results.dots[#self.results.dots+1] = dots
    return dots
end

function mt:createLocal(key, source, var)
    if key == nil then
        return nil
    end
    if not var then
        var = self:createVar('local', key, source)
        self:addInfo(var, 'local', source)
    end
    var.redefinition = self.env.var[key]
    self.env.var[key] = var
    return var
end

function mt:addField(parent, key, source)
    if parent == nil or key == nil then
        return nil
    end
    assert(source)
    local var = parent.childs[key]
    if not var then
        var = self:createVar('field', key, source)
        parent.childs[key] = var
        var.parent = parent
    end
    return var
end

function mt:getField(parent, key, source)
    if parent == nil or key == nil then
        return nil
    end
    local var
    if parent.childs then
        var = parent.childs[key]
    end
    if not var and source then
        var = self:addField(parent, key, source)
    end
    return var
end

function mt:checkName(name)
    local var = self:getVar(name[1], name)
    self:addInfo(var, 'get', name)
    return var
end

function mt:checkDots(source)
    local dots = self.env.dots
    if not dots then
        return
    end
    self:addInfo(dots, 'get', source)
end

function mt:searchCall(call, simple, i)
    local results = {}
    for i, exp in ipairs(call) do
        results[i] = self:searchExp(exp)
    end
    
    -- 特殊处理 setmetatable
    if i == 2 and simple[1][1] == 'setmetatable' then
        local obj = results[1]
        local metatable = results[2]
        if metatable then
            local index = self:getField(metatable, '__index')
            if obj then
                self:setMeta(obj, index)
                return obj
            else
                return index
            end
        else
            return obj
        end
    end
    return nil
end

function mt:searchSimple(simple)
    local name = simple[1]
    local var
    if name.type == 'name' then
        var = self:getVar(name[1], name)
    end
    self:searchExp(simple[1])
    for i = 2, #simple do
        local obj = simple[i]
        local tp = obj.type
        if     tp == 'call' then
            var = self:searchCall(obj, simple, i)
        elseif tp == ':' then
        elseif tp == 'name' then
            if obj.index then
                self:checkName(obj)
                var = nil
            else
                var = self:getField(var, obj[1], obj)
                self:addInfo(var, 'get', obj)
            end
        else
            if obj.index and (obj.type == 'string' or obj.type == 'number' or obj.type == 'boolean') then
                var = self:getField(var, obj[1], obj)
                self:addInfo(var, 'get', obj)
            else
                self:searchExp(obj)
                var = nil
            end
        end
    end
    return var
end

function mt:searchBinary(exp)
    self:searchExp(exp[1])
    self:searchExp(exp[2])
end

function mt:searchUnary(exp)
    self:searchExp(exp[1])
end

function mt:searchTable(exp)
    local tbl = {
        type = 'table',
        childs = {},
    }
    for _, obj in ipairs(exp) do
        if obj.type == 'pair' then
            local key, value = obj[1], obj[2]
            local res = self:searchExp(value)
            local var = self:addField(tbl, key[1], key)
            self:setTable(var, res)
            self:addInfo(var, 'set', key)
        else
            self:searchExp(obj)
        end
    end
    return tbl
end

function mt:searchExp(exp)
    local tp = exp.type
    if     tp == 'nil' then
    elseif tp == 'string' then
    elseif tp == 'boolean' then
    elseif tp == 'number' then
    elseif tp == 'name' then
        return self:checkName(exp)
    elseif tp == 'simple' then
        return self:searchSimple(exp)
    elseif tp == 'binary' then
        self:searchBinary(exp)
    elseif tp == 'unary' then
        self:searchUnary(exp)
    elseif tp == '...' then
        self:checkDots(exp)
    elseif tp == 'function' then
        self:searchFunction(exp)
    elseif tp == 'table' then
        return self:searchTable(exp)
    end
    return nil
end

function mt:searchReturn(action)
    for _, exp in ipairs(action) do
        self:searchExp(exp)
    end
end

function mt:setTable(var, tbl)
    if not var or not tbl then
        return
    end
    var.childs = tbl.childs
    for _, child in pairs(tbl.childs) do
        child.parent = var
    end
end

function mt:setMeta(var, meta)
    if not var or not meta then
        return
    end
    var.childs.meta = meta
    meta.childs.meta = var
end

function mt:markSimple(simple)
    local name = simple[1]
    local var
    if name.type == 'name' then
        var = self:getVar(name[1], name)
    end
    self:searchExp(simple[1])
    for i = 2, #simple do
        local obj = simple[i]
        local tp  = obj.type
        if     tp == 'call' then
            var = self:searchCall(obj, simple, i)
        elseif tp == ':' then
            var = self:createLocal('self', simple[i-1], self:getVar(simple[i-1][1]))
            var.disableRename = true
        elseif tp == 'name' then
            if obj.index then
                self:checkName(obj)
                var = nil
            else
                if i == #simple then
                    var = self:addField(var, obj[1], obj)
                    self:addInfo(var, 'set', obj)
                else
                    var = self:getField(var, obj[1], obj)
                    self:addInfo(var, 'get', obj)
                end
            end
        else
            if obj.index and (obj.type == 'string' or obj.type == 'number' or obj.type == 'boolean') then
                if i == #simple then
                    var = self:addField(var, obj[1], obj)
                    self:addInfo(var, 'set', obj)
                else
                    var = self:getField(var, obj[1], obj)
                    self:addInfo(var, 'get', obj)
                end
            else
                self:searchExp(obj)
                var = nil
            end
        end
    end
    return var
end

function mt:markSet(simple, tbl)
    if simple.type == 'name' then
        local var = self:getVar(simple[1], simple)
        self:addInfo(var, 'set', simple)
        self:setTable(var, tbl)
    else
        local var = self:markSimple(simple)
        self:setTable(var, tbl)
    end
end

function mt:markLocal(name, tbl)
    if name.type == 'name' then
        local str = name[1]
        -- 创建一个局部变量
        local var = self:createLocal(str, name)
        self:setTable(var, tbl)
    elseif name.type == '...' then
        local dots = self:createDots()
        self:addInfo(dots, 'local', name)
        self.env.dots = dots
    elseif name.type == ':' then
        -- 创建一个局部变量
        self:createLocal('self', name)
    end
end

function mt:forList(list, callback)
    if not list then
        return
    end
    if list.type == 'list' then
        for i = 1, #list do
            callback(list[i])
        end
    else
        callback(list)
    end
end

function mt:markSets(action)
    local keys = action[1]
    local values = action[2]
    local results = {}
    -- 要先计算赋值
    local i = 0
    self:forList(values, function (value)
        i = i + 1
        results[i] = self:searchExp(value)
    end)
    local i = 0
    self:forList(keys, function (key)
        i = i + 1
        self:markSet(key, results[i])
    end)
end

function mt:markLocals(action)
    local keys = action[1]
    local values = action[2]
    local results = {}
    -- 要先计算赋值
    local i = 0
    self:forList(values, function (value)
        i = i + 1
        results[i] = self:searchExp(value)
    end)
    local i = 0
    self:forList(keys, function (key)
        i = i + 1
        self:markLocal(key, results[i])
    end)
end

function mt:searchIfs(action)
    for _, block in ipairs(action) do
        self.env:push()
        if block.filter then
            self:searchExp(block.filter)
        end
        self:searchActions(block)
        self.env:pop()
    end
end

function mt:searchLoop(action)
    self.env:push()
    self:markLocal(action.arg)
    self:searchExp(action.min)
    self:searchExp(action.max)
    if action.step then
        self:searchExp(action.step)
    end
    self:searchActions(action)
    self.env:pop()
end

function mt:searchIn(action)
    self:forList(action.exp, function (exp)
        self:searchExp(exp)
    end)
    self.env:push()
    self:forList(action.arg, function (arg)
        self:markLocal(arg)
    end)
    self:searchActions(action)
    self.env:pop()
end

function mt:searchDo(action)
    self.env:push()
    self:searchActions(action)
    self.env:pop()
end

function mt:searchWhile(action)
    self:searchExp(action.filter)
    self.env:push()
    self:searchActions(action)
    self.env:pop()
end

function mt:searchRepeat(action)
    self.env:push()
    self:searchActions(action)
    self:searchExp(action.filter)
    self.env:pop()
end

function mt:searchFunction(func)
    self.env:push()
    self.env:cut 'dots'
    self.env.label = {}
    if func.name then
        self:markSet(func.name)
    end
    self:forList(func.arg, function (arg)
        self:markLocal(arg)
    end)
    self:searchActions(func)
    self.env:pop()
end

function mt:searchLocalFunction(func)
    if func.name then
        self:markLocal(func.name)
    end
    self.env:push()
    self:forList(func.arg, function (arg)
        self:markLocal(arg)
    end)
    self:searchActions(func)
    self.env:pop()
end

function mt:markLabel(label)
    local str = label[1]
    if not self.env.label[str] then
        self.env.label[str] = self:createLabel(str)
    end
    self:addInfo(self.env.label[str], 'set', label)
end

function mt:searchGoTo(obj)
    local str = obj[1]
    if not self.env.label[str] then
        self.env.label[str] = self:createLabel(str)
    end
    self:addInfo(self.env.label[str], 'goto', obj)
end

function mt:searchAction(action)
    local tp = action.type
    if     tp == 'do' then
        self:searchDo(action)
    elseif tp == 'break' then
    elseif tp == 'return' then
        self:searchReturn(action)
    elseif tp == 'label' then
        self:markLabel(action)
    elseif tp == 'goto' then
        self:searchGoTo(action)
    elseif tp == 'set' then
        self:markSets(action)
    elseif tp == 'local' then
        self:markLocals(action)
    elseif tp == 'simple' then
        self:searchSimple(action)
    elseif tp == 'if' then
        self:searchIfs(action)
    elseif tp == 'loop' then
        self:searchLoop(action)
    elseif tp == 'in' then
        self:searchIn(action)
    elseif tp == 'while' then
        self:searchWhile(action)
    elseif tp == 'repeat' then
        self:searchRepeat(action)
    elseif tp == 'function' then
        self:searchFunction(action)
    elseif tp == 'localfunction' then
        self:searchLocalFunction(action)
    end
end

function mt:searchActions(actions)
    for _, action in ipairs(actions) do
        self:searchAction(action)
    end
    return nil
end

return function (ast)
    if not ast then
        return nil
    end
    local searcher = setmetatable({
        env = env {
            var = {},
            usable = {}
        },
        results = {
            labels = {},
            vars = {},
            dots = {},
        }
    }, mt)
    searcher.env.label = {}
    searcher:createLocal('_ENV', { start = -1, finish = -1 })
    searcher:searchActions(ast)

    return searcher.results
end
