local findResult = require 'matcher.find_result'

local function tryMeta(var)
    local keys = {}
    repeat
        if var.childs.meta then
            local metavar = var.childs.meta
            for i = #keys, 1, -1 do
                local key = keys[i]
                metavar = metavar.childs[key]
                if not metavar then
                    return nil
                end
            end
            return metavar
        end
        keys[#keys+1] = var.key
        var = var.parent
    until not var
    return nil
end

local function parseResult(result)
    local positions = {}
    local tp = result.type
    if     tp == 'local' then
        for _, info in ipairs(result.object) do
            if info.type == 'local' then
                positions[#positions+1] = {info.source.start, info.source.finish}
            end
        end
    elseif tp == 'field' then
        for _, info in ipairs(result.object) do
            if info.type == 'set' then
                positions[#positions+1] = {info.source.start, info.source.finish}
            end
        end
        --local metavar = tryMeta(var)
        --if metavar then
        --    for _, info in ipairs(metavar) do
        --        if info.type == 'set' then
        --            positions[#positions+1] = {info.source.start, --info.source.finish}
        --        end
        --    end
        --end
    elseif tp == 'label' then
        for _, info in ipairs(result.object) do
            if info.type == 'set' then
                positions[#positions+1] = {info.source.start, info.source.finish}
            end
        end
    else
        error('Unknow result type:' .. result.type)
    end
    return positions
end

return function (results, pos)
    local result = findResult(results, pos)
    if not result then
        return nil
    end
    local positions = parseResult(result)
    return positions
end
