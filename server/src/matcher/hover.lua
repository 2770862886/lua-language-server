local findResult = require 'matcher.find_result'
local findLib    = require 'matcher.find_lib'

local Cache = {}
local OoCache = {}

local function buildArgs(lib, oo)
    if not lib.args then
        return ''
    end
    local start
    if oo then
        start = 2
    else
        start = 1
    end
    local strs = {}
    for i = start, #lib.args do
        local arg = lib.args[i]
        if arg.optional then
            if i > start then
                strs[#strs+1] = ' ['
            else
                strs[#strs+1] = '['
            end
        end
        if i > start then
            strs[#strs+1] = ', '
        end
        if arg.name then
            strs[#strs+1] = ('%s: '):format(arg.name)
        end
        strs[#strs+1] = arg.type or 'any'
        if arg.default then
            strs[#strs+1] = ('(%q)'):format(arg.default)
        end
        if arg.optional == 'self' then
            strs[#strs+1] = ']'
        end
    end
    for _, arg in ipairs(lib.args) do
        if arg.optional == 'after' then
            strs[#strs+1] = ']'
        end
    end
    return table.concat(strs)
end

local function buildReturns(lib)
    if not lib.returns then
        return ''
    end
    local strs = {}
    for i, rtn in ipairs(lib.returns) do
        if rtn.optional then
            if i > 1 then
                strs[#strs+1] = ' ['
            else
                strs[#strs+1] = '['
            end
        end
        if i > 1 then
            strs[#strs+1] = ', '
        end
        if rtn.name then
            strs[#strs+1] = ('%s: '):format(rtn.name)
        end
        strs[#strs+1] = rtn.type or 'any'
        if rtn.default then
            strs[#strs+1] = ('(%q)'):format(rtn.default)
        end
        if rtn.optional == 'self' then
            strs[#strs+1] = ']'
        end
    end
    for _, rtn in ipairs(lib.returns) do
        if rtn.optional == 'after' then
            strs[#strs+1] = ']'
        end
    end
    return '\n  -> ' .. table.concat(strs)
end

local function buildEnum(lib)
    if not lib.enums then
        return ''
    end
    local container = table.container()
    for _, enum in ipairs(lib.enums) do
        if not enum.name or not enum.enum then
            goto NEXT_ENUM
        end
        if not container[enum.name] then
            container[enum.name] = {}
            if lib.args then
                for _, arg in ipairs(lib.args) do
                    if arg.name == enum.name then
                        container[enum.name].type = arg.type
                        break
                    end
                end
            end
        end
        table.insert(container[enum.name], enum)
        ::NEXT_ENUM::
    end
    local strs = {}
    for name, enums in pairs(container) do
        strs[#strs+1] = ('\n%s: %s'):format(name, enums.type or '')
        for _, enum in ipairs(enums) do
            if enum.default then
                strs[#strs+1] = '\n  -> '
            else
                strs[#strs+1] = '\n   | '
            end
            strs[#strs+1] = ('%q -- %s'):format(enum.enum, enum.description or '')
        end
    end
    return table.concat(strs)
end

local function buildFunctionHover(lib, fullKey, oo)
    local title = ('function %s(%s)%s'):format(fullKey, buildArgs(lib, oo), buildReturns(lib))
    local enum = buildEnum(lib)
    local tip = lib.description or ''
    return ([[
```lua
%s
```
%s
```lua
%s
```
]]):format(title, tip, enum)
end

local function buildField(lib)
    if not lib.fields then
        return ''
    end
    local strs = {}
    for _, field in ipairs(lib.fields) do
        strs[#strs+1] = ('\n%s: %s -- %s'):format(field.field, field.type, field.description or '')
    end
    return table.concat(strs)
end

local function buildTableHover(lib, fullKey)
    local title = ('table %s'):format(fullKey)
    local field = buildField(lib)
    local tip = lib.description or ''
    return ([[
```lua
%s
```
%s
```lua
%s
```
]]):format(title, tip, field)
end

local function getLibHover(lib, fullKey, oo)
    local cache = oo and OoCache or Cache

    if not cache[lib] then
        if lib.type == 'function' then
            cache[lib] = buildFunctionHover(lib, fullKey, oo) or ''
        elseif lib.type == 'table' then
            cache[lib] = buildTableHover(lib, fullKey) or ''
        elseif lib.type == 'string' then
            cache[lib] = lib.description or ''
        else
            cache[lib] = ''
        end
    end

    return cache[lib]
end

local function buildValueName(result, source)
    local func = result.value
    local declarat = func.declarat or source
    if declarat then
        local key
        if declarat.type == 'name' then
            key = declarat[1]
        elseif declarat.type == 'string' then
            key = ('%q'):format(declarat[1])
        elseif declarat.type == 'number' or declarat.type == 'boolean' then
            key = tostring(declarat[1])
        else
            key = '?'
        end
        if source.object then
            return declarat.parentName .. ':' .. key
        else
            if declarat.parentName then
                if declarat.index then
                    return declarat.parentName .. '[' .. key .. ']'
                else
                    return declarat.parentName .. '.' .. key
                end
            else
                return key
            end
        end
    end
    return result.key or ''
end

local function buildValueArgs(result)
    local func = result.value
    local names = {}
    local values = {}
    if func.args then
        for i, arg in ipairs(func.args) do
            if arg.type == '...' then
                names[i] = '...'
            else
                names[i] = arg.key
            end
        end
    end
    if func.argValues then
        for i, value in ipairs(func.argValues) do
            values[i] = value.type
            if values[i] == 'nil' then
                values[i] = 'any'
            end
        end
    end
    local strs = {}
    for i = 1, math.max(#names, #values) do
        local name = names[i] or '?'
        local value = values[i] or 'any'
        strs[i] = name .. ': ' .. value
    end
    return table.concat(strs, ', ')
end

local function buildValueReturns(result)
    local func = result.value
    if not func.hasReturn then
        return ''
    end
    local strs = {}
    for i, rtn in ipairs(func.returns) do
        strs[i] = rtn.type
        if strs[i] == 'nil' then
            strs[i] = 'any'
        end
    end
    return '\n  -> ' .. table.concat(strs, ', ')
end

local function buildValueFunctionHover(result, source)
    local name = buildValueName(result, source)
    local args = buildValueArgs(result)
    local returns = buildValueReturns(result)
    local title = ('function %s(%s)%s'):format(name, args, returns)
    return ([[
```lua
%s
```
]]):format(title)
end

local function getValueHover(result, source)
    if result.value.type == 'function' then
        return buildValueFunctionHover(result, source)
    end
end

return function (vm, pos)
    local result, source = findResult(vm, pos)
    if not result then
        return nil
    end

    local lib, fullKey, oo = findLib(result)
    if lib then
        local hover = getLibHover(lib, fullKey, oo)
        return hover
    end

    if result.value then
        return getValueHover(result, source)
    end
end
