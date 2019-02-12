local createValue = require 'vm.value'
local createFunction = require 'vm.function'

local CHILD_CACHE = {}

local buildLibValue
local buildLibChild

function buildLibValue(lib)
    local tp = lib.type
    local value
    if     tp == 'table' then
        value = createValue('table')
    elseif tp == 'function' then
        value = createValue('function')
        local func = createFunction()
        value:setFunction(func)
        if lib.returns then
            for i, rtn in ipairs(lib.returns) do
                if rtn.type == '...' then
                    func:returnDots(i)
                else
                    func:setReturn(i, buildLibValue(rtn))
                end
            end
        end
    elseif tp == 'string' then
        value = createValue('string')
    elseif tp == 'boolean' then
        value = createValue('boolean')
    elseif tp == 'number' then
        value = createValue('number')
    elseif tp == 'integer' then
        value = createValue('integer')
    elseif tp == 'nil' then
        value = createValue('nil')
    else
        value = createValue(tp or 'any')
    end
    value:setLib(lib)

    if lib.child then
        for fName, fLib in pairs(lib.child) do
            local fValue = buildLibValue(fLib)
            value:rawSet(fName, fValue)
        end
    end

    return value
end

function buildLibChild(lib)
    if CHILD_CACHE[lib] then
        return CHILD_CACHE[lib]
    end
    local child = {}
    for fName, fLib in pairs(lib.child) do
        local fValue = buildLibValue(fLib)
        child[fName] = fValue
    end
    CHILD_CACHE[lib] = child
    return child
end

return {
    value = buildLibValue,
    child = buildLibChild,
}
