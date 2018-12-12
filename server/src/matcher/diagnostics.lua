local function searchUnusedLocals(results, callback)
    for _, var in ipairs(results.locals) do
        if var.key == 'self'
        or var.key == '_'
        or var.key == '_ENV'
        then
            goto NEXT_VAR
        end
        for _, info in ipairs(var) do
            if info.type == 'get' then
                goto NEXT_VAR
            end
            if info.type == 'local' then
                if info.source.start == 0 then
                    goto NEXT_VAR
                end
            end
        end
        callback(var.source.start, var.source.finish, var.key)
        ::NEXT_VAR::
    end
end

local function searchUndefinedGlobal(results, callback)
    local env = results.locals[1]
    for index, field in pairs(env.value.child) do
        if field.value.lib then
            goto NEXT_VAR
        end
        if type(index) == 'string' then
            if index:lower() == 'log' then
                goto NEXT_VAR
            end
            if not index:find '%l' then
                goto NEXT_VAR
            end
        end
        for _, info in ipairs(field) do
            if info.type == 'set' then
                goto NEXT_VAR
            end
        end
        for _, info in ipairs(field) do
            if info.type == 'get' then
                callback(info.source.start, info.source.finish, tostring(index))
            end
        end
        ::NEXT_VAR::
    end
end

local function searchUnusedLabel(results, callback)
    for _, label in ipairs(results.labels) do
        for _, info in ipairs(label) do
            if info.type == 'goto' then
                goto NEXT_LABEL
            end
        end
        for _, info in ipairs(label) do
            if info.type == 'set' then
                callback(info.source.start, info.source.finish, label.key)
            end
        end
        ::NEXT_LABEL::
    end
end

local function serachSpaces(lines, callback)
    for i = 1, #lines do
        local line = lines:line(i)

        if line:find '^[ \t]+$' then
            local start, finish = lines:range(i)
            callback(start, finish, 'Line with spaces only') -- LOCALE
            goto NEXT_LINE
        end

        local pos = line:find '[ \t]+$'
        if pos then
            local start, finish = lines:range(i)
            callback(start + pos - 1, finish, 'Line with postspace') -- LOCALE
            goto NEXT_LINE
        end
        ::NEXT_LINE::
    end
end

local function searchRedefinition(results, uri, callback)
    for _, var in ipairs(results.locals) do
        if var.key == '_'
        or var.key == '_ENV'
        then
            goto NEXT_VAR
        end
        local shadow = var.shadow
        if not shadow then
            goto NEXT_VAR
        end
        -- 如果多次重定义，则不再警告
        if #shadow >= 3 then
            goto NEXT_VAR
        end
        local related = {}
        for i = 1, #shadow do
            related[i] = {
                start  = shadow[i].source.start,
                finish = shadow[i].source.finish,
                uri    = uri,
            }
        end
        callback(var.source.start, var.source.finish, var.key, related)
        ::NEXT_VAR::
    end
end

local function searchNewLineCall(results, lines, callback)
    for _, call in ipairs(results.calls) do
        if not call.nextObj then
            goto NEXT_CALL
        end
        if not call.lastObj.start then
            goto NEXT_CALL
        end
        local callline = lines:rowcol(call.call.start)
        local lastline = lines:rowcol(call.lastObj.finish)
        if callline > lastline then
            callback(call.call.start, call.call.finish)
        end
        ::NEXT_CALL::
    end
end

return function (vm, lines, uri)
    local datas = {}
    local results = vm.results
    -- 未使用的局部变量
    searchUnusedLocals(results, function (start, finish, key)
        datas[#datas+1] = {
            start   = start,
            finish  = finish,
            level   = 'Information',
            message = ('Unused local `%s`'):format(key), -- LOCALE
        }
    end)
    -- 读取未定义全局变量
    searchUndefinedGlobal(results, function (start, finish, key)
        datas[#datas+1] = {
            start   = start,
            finish  = finish,
            level   = 'Warning',
            message = ('Undefined global `%s`'):format(key), -- LOCALE
        }
    end)
    -- 未使用的Label
    searchUnusedLabel(results, function (start, finish, key)
        datas[#datas+1] = {
            start   = start,
            finish  = finish,
            level   = 'Information',
            message = ('Unused label `%s`'):format(key), -- LOCALE
        }
    end)
    -- 只有空格与制表符的行，以及后置空格
    serachSpaces(lines, function (start, finish, message)
        datas[#datas+1] = {
            start   = start,
            finish  = finish,
            level   = 'Information',
            message = message,
        }
    end)
    -- 重定义局部变量
    searchRedefinition(results, uri, function (start, finish, key, related)
        datas[#datas+1] = {
            start   = start,
            finish  = finish,
            level   = 'Information',
            message = ('Redefined local `%s`'):format(key), -- LOCALE
            related = related,
        }
    end)
    -- 以括号开始的一行（可能被误解析为了上一行的call）
    searchNewLineCall(results, lines, function (start, finish)
        datas[#datas+1] = {
            start   = start,
            finish  = finish,
            level   = 'Warning',
            message = 'Parsed as function call for the previous line. It may be necessary to add a `;` before.', -- LOCALE
        }
    end)
    return datas
end
