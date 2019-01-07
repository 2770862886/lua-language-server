local findResult = require 'core.find_result'
local hover = require 'core.hover'

local CompletionItemKind = {
    Text = 1,
    Method = 2,
    Function = 3,
    Constructor = 4,
    Field = 5,
    Variable = 6,
    Class = 7,
    Interface = 8,
    Module = 9,
    Property = 10,
    Unit = 11,
    Value = 12,
    Enum = 13,
    Keyword = 14,
    Snippet = 15,
    Color = 16,
    File = 17,
    Reference = 18,
    Folder = 19,
    EnumMember = 20,
    Constant = 21,
    Struct = 22,
    Event = 23,
    Operator = 24,
    TypeParameter = 25,
}

local function matchKey(me, other)
    if me == other then
        return false
    end
    if me == '' then
        return true
    end
    if #me > #other then
        return false
    end
    local lMe = me:lower()
    local lOther = other:lower()
    if lMe:sub(1, 1) ~= lOther:sub(1, 1) then
        return false
    end
    if lMe == lOther:sub(1, #lMe) then
        return true
    end
    local used = {
        [1] = true,
    }
    local cur = 2
    local lookup
    local researched
    for i = 2, #lMe do
        local c = lMe:sub(i, i)
        -- 1. 看当前字符是否匹配
        if c == lOther:sub(cur, cur) then
            used[cur] = true
            goto NEXT
        end
        -- 2. 看前一个字符是否匹配
        if not used[cur-1] then
            if c == lOther:sub(cur-1, cur-1) then
                used[cur-1] = true
                goto NEXT
            end
        end
        -- 3. 向后找这个字
        lookup = lOther:find(c, cur+1, true)
        if lookup then
            cur = lookup
            used[cur] = true
            goto NEXT
        end

        -- 4. 重新搜索整个字符串，但是只允许1次，否则失败.如果找不到也失败
        if researched then
            return false
        else
            researched = true
            for j = 2, cur - 2 do
                if c == lOther:sub(j, j) then
                    used[j] = true
                    goto NEXT
                end
            end
            return false
        end
        -- 5. 找到下一个可用的字，如果超出长度就算成功
        ::NEXT::
        repeat
            cur = cur + 1
        until not used[cur]
        if cur > #lOther then
            break
        end
    end
    return true
end

local function searchLocals(vm, pos, name, callback)
    for _, loc in ipairs(vm.results.locals) do
        if loc.source.start == 0 then
            goto CONTINUE
        end
        if loc.source.start <= pos and loc.close >= pos then
            if matchKey(name, loc.key) then
                callback(loc)
            end
        end
        ::CONTINUE::
    end
end

local function searchFields(name, parent, object, callback)
    if not parent or not parent.value or not parent.value.child then
        return
    end
    for key, field in pairs(parent.value.child) do
        if type(key) ~= 'string' then
            goto CONTINUE
        end
        if object then
            if not field.value or field.value.type ~= 'function' then
                goto CONTINUE
            end
        end
        if type(name) == 'string' and matchKey(name, key) then
            callback(field)
        end
        ::CONTINUE::
    end
end

local KEYS = {'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'goto', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while', 'toclose'}
local function searchKeyWords(name, callback)
    for _, key in ipairs(KEYS) do
        if matchKey(name, key) then
            callback(key)
        end
    end
end

local function getKind(var, default)
    local value = var.value
    if default == CompletionItemKind.Variable then
        if value.type == 'function' then
            return CompletionItemKind.Function
        end
    end
    if default == CompletionItemKind.Field then
        local tp = type(value.value)
        if tp == 'number' or tp == 'integer' or tp == 'string' then
            return CompletionItemKind.Enum
        end
        if value.type == 'function' then
            if var.parent and var.parent.value and var.parent.value.ENV ~= true then
                return CompletionItemKind.Method
            else
                return CompletionItemKind.Function
            end
        end
    end
    return default
end

local function getDetail(var)
    local tp = type(var.value.value)
    if tp == 'boolean' then
        return ('= %q'):format(var.value.value)
    elseif tp == 'number' then
        if math.type(var.value.value) == 'integer' then
            return ('= %q'):format(var.value.value)
        else
            local str = ('= %.10f'):format(var.value.value)
            local dot = str:find('.', 1, true)
            local suffix = str:find('[0]+$', dot+2)
            if suffix then
                return str:sub(1, suffix-1)
            else
                return str
            end
        end
    elseif tp == 'string' then
        return ('= %q'):format(var.value.value)
    end
    return nil
end

local function getDocument(var, source)
    if var.value.type == 'function' then
        return {
            kind = 'markdown',
            value = hover(var, source),
        }
    end
    return nil
end

local function searchAsLocal(vm, pos, result, callback)
    searchFields(result.key, vm.results.locals[1], nil, function (var)
        callback(var, CompletionItemKind.Variable)
    end)

    -- 支持 local function
    if matchKey(result.key, 'function') then
        callback('function', CompletionItemKind.Keyword)
    end
end

local function searchAsArg(vm, pos, result, callback)
    searchFields(result.key, vm.results.locals[1], nil, function (var)
        if var.value.lib then
            return
        end
        callback(var, CompletionItemKind.Variable)
    end)
end

local function searchAsGlobal(vm, pos, result, callback)
    if result.key == '' then
        return
    end
    searchLocals(vm, pos, result.key, function (var)
        callback(var, CompletionItemKind.Variable)
    end)
    searchFields(result.key, vm.results.locals[1], nil, function (var)
        callback(var, CompletionItemKind.Field)
    end)
    searchKeyWords(result.key, function (name)
        callback(name, CompletionItemKind.Keyword)
    end)
end

local function searchAsSuffix(result, callback)
    searchFields(result.key, result.parent, result.source.object, function (var)
        callback(var, CompletionItemKind.Field)
    end)
end

local function searchInArg(vm, inCall, inString, callback)
    local lib = inCall.func.lib
    if not lib then
        return
    end

    -- require列举出可以引用到的文件
    if lib.special == 'require' then
        if not vm.lsp or not vm.lsp.workspace or not inString then
            return
        end
        local results = vm.lsp.workspace:matchPath(vm.uri, inString[1])
        if not results then
            return
        end
        for _, v in ipairs(results) do
            if v ~= inString[1] then
                callback(v, CompletionItemKind.File, {
                    textEdit = {
                        start = inString.start+1,
                        finish = inString.finish-1,
                        newText = ('%q'):format(v):sub(2, -2),
                    }
                })
            end
        end
    end

    -- 其他库函数，根据参数位置找枚举值
    if lib.args and lib.enums then
        local arg = lib.args[inCall.select]
        local name = arg and arg.name
        for _, enum in ipairs(lib.enums) do
            if enum.name == name and enum.enum then
                if inString then
                    callback(enum.enum, CompletionItemKind.EnumMember, {
                        documentation = enum.description
                    })
                else
                    callback(('%q'):format(enum.enum), CompletionItemKind.EnumMember, {
                        documentation = enum.description
                    })
                end
            end
        end
    end
end

local function searchAsIndex(vm, pos, result, callback)
    searchLocals(vm, pos, result.key, function (var)
        callback(var, CompletionItemKind.Variable)
    end)
    for _, index in ipairs(vm.results.indexs) do
        if matchKey(result.key, index.key) then
            callback(index.key, CompletionItemKind.Property)
        end
    end
    searchFields(result.key, vm.results.locals[1], nil, function (var)
        callback(var, CompletionItemKind.Field)
    end)
end

local function findClosePos(vm, pos)
    local curDis = math.maxinteger
    local parent = nil
    local function found(object, source)
        local dis = pos - source.finish
        if dis > 1 and dis < curDis then
            curDis = dis
            parent = object
        end
    end
    for sources, object in pairs(vm.results.sources) do
        if sources.type == 'multi-source' then
            for _, source in ipairs(sources) do
                if source.type ~= 'simple' then
                    found(object, source)
                end
            end
        else
            found(object, sources)
        end
    end
    if not parent then
        return nil
    end
    if parent.type ~= 'local' and parent.type ~= 'field' then
        return nil
    end
    -- 造个假的 DirtyName
    local source = {
        type = 'name',
        start = pos,
        finish = pos,
        [1]    = '',
    }
    local result = {
        type = 'field',
        parent = parent,
        key = '',
        source = source,
    }
    return result, source
end

local function isContainPos(obj, pos)
    if obj.start <= pos and obj.finish + 1 >= pos then
        return true
    end
    return false
end

local function findString(vm, pos)
    for _, source in ipairs(vm.results.strings) do
        if isContainPos(source, pos) then
            return source
        end
    end
    return nil
end

local function findArgCount(args, pos)
    for i, arg in ipairs(args) do
        if isContainPos(arg, pos) then
            return i
        end
    end
    return #args + 1
end

-- 找出范围包含pos的call
local function findCall(vm, pos)
    local results = {}
    for _, call in ipairs(vm.results.calls) do
        if isContainPos(call.args, pos) then
            local n = findArgCount(call.args, pos)
            local var = vm.results.sources[call.lastObj]
            if var then
                results[#results+1] = {
                    func = call.func,
                    var = var,
                    source = call.lastObj,
                    select = n,
                    args = call.args,
                }
            end
        end
    end
    if #results == 0 then
        return nil
    end
    -- 可能处于 'func1(func2(' 的嵌套中，因此距离越远的函数层级越低
    table.sort(results, function (a, b)
        return a.args.start < b.args.start
    end)
    return results[#results]
end

local function makeList(source)
    local list = {}
    local mark = {}
    local function callback(var, defualt, data)
        local key
        if type(var) == 'string' then
            key = var
        else
            key = var.key
        end
        if mark[key] then
            return
        end
        mark[key] = true
        data = data or {}
        list[#list+1] = data
        if var == key then
            data.label = var
            data.kind = defualt
        else
            data.label = var.key
            data.kind = getKind(var, defualt)
            data.detail = data.detail or getDetail(var)
            data.documentation = data.documentation or getDocument(var, source)
        end
    end
    return list, callback
end

local function searchInResult(result, source, vm, pos, callback)
    if result.type == 'local' then
        if source.isArg then
            searchAsArg(vm, pos, result, callback)
        elseif source.isLocal then
            searchAsLocal(vm, pos, result, callback)
        else
            searchAsGlobal(vm, pos, result, callback)
        end
    elseif result.type == 'field' then
        if source.isIndex then
            searchAsIndex(vm, pos, result, callback)
        elseif result.parent and result.parent.value and result.parent.value.ENV == true then
            searchAsGlobal(vm, pos, result, callback)
        else
            searchAsSuffix(result, callback)
        end
    end
end

local function searchSpecial(vm, pos, callback)
    -- 尝试 #
    local result, source = findResult(vm, pos, 2)
    if source and source.type == 'index'
        and result.source and result.source.op == '#'
    then
        local name = {}
        local var = result
        while true do
            var = var.parent
            if not var then
                break
            end
            if var.value and var.value.ENV then
                break
            end
            local key = var.key
            if type(key) ~= 'string' or key == '' then
                return
            end
            table.insert(name, 1, key)
        end
        local label = table.concat(name, '.') .. '+1'
        callback(label, CompletionItemKind.Snippet, {
            textEdit = {
                start = result.source.start + 1,
                finish = source.finish,
                newText = ('%s] = '):format(label),
            }
        })
    end
end

return function (vm, pos)
    local result, source = findResult(vm, pos)
    if not result then
        result, source = findClosePos(vm, pos)
    end

    if not result then
        return nil
    end

    local list, callback = makeList(source)
    local inCall = findCall(vm, pos)
    local inString = findString(vm, pos)
    if inCall then
        searchInArg(vm, inCall, inString, callback)
    end
    searchSpecial(vm, pos, callback)
    if not inString then
        searchInResult(result, source, vm, pos, callback)
    end
    if #list == 0 then
        return nil
    end
    return list
end
