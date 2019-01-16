local function buildValueArgs(func, oo, select)
    local names = {}
    local values = {}
    if func.args then
        for i, arg in ipairs(func.args) do
            names[i] = arg.key
        end
    end
    if func.argValues then
        for i, value in ipairs(func.argValues) do
            values[i] = value.type
        end
    end
    local strs = {}
    local start = 1
    if oo then
        start = 2
        if select then
            select = select + 1
        end
    end
    local max
    if func.built then
        max = #names
    else
        max = math.max(#names, #values)
    end
    for i = start, max do
        if i > start then
            strs[#strs+1] = ', '
        end
        local name = names[i]
        local value = values[i] or 'any'
        if i == select then
            strs[#strs+1] = '@ARG'
        end
        if name then
            strs[#strs+1] = name .. ': ' .. value
        else
            strs[#strs+1] = value
        end
        if i == select then
            strs[#strs+1] = '@ARG'
        end
    end
    if func.hasDots then
        if max > 0 then
            strs[#strs+1] = ', '
        end
        strs[#strs+1] = '...'
    end
    local text = table.concat(strs)
    local argLabel = {}
    for i = 1, 2 do
        local pos = text:find('@ARG', 1, true)
        if pos then
            if i == 1 then
                argLabel[i] = pos
            else
                argLabel[i] = pos - 1
            end
            text = text:sub(1, pos-1) .. text:sub(pos+4)
        end
    end
    if #argLabel == 0 then
        argLabel = nil
    end
    return text, argLabel
end

local function buildValueReturns(func)
    if not func.hasReturn then
        return ''
    end
    local strs = {}
    if func.returns then
        for i, rtn in ipairs(func.returns) do
            strs[i] = rtn.type
        end
    end
    if #strs == 0 then
        strs[1] = 'any'
    end
    return '\n  -> ' .. table.concat(strs, ', ')
end

return function (name, func, oo, select)
    local args, argLabel = buildValueArgs(func, oo, select)
    local returns = buildValueReturns(func)
    local headLen = #('function %s('):format(name)
    local title = ('function %s(%s)%s'):format(name, args, returns)
    if argLabel then
        argLabel[1] = argLabel[1] + headLen
        argLabel[2] = argLabel[2] + headLen
    end
    return {
        label = title,
        argLabel = argLabel,
    }
end
