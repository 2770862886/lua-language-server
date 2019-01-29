local function isContainPos(obj, pos)
    if obj.start <= pos and obj.finish + 1 >= pos then
        return true
    end
    return false
end

local function isValidSource(source)
    return source.type ~= 'simple'
end

local function findAtPos(results, pos, level)
    local res = {}
    for _, source in ipairs(results.sources) do
        if isValidSource(source) and isContainPos(source, pos) then
            res[#res+1] = {
                object = source.object,
                source = source,
                range = source.finish - source.start,
            }
        end
    end
    if #res == 0 then
        return nil
    end
    table.sort(res, function (a, b)
        return a.range < b.range
    end)
    local data = res[level or 1]
    if not data then
        return nil
    end
    return data.object, data.source
end

return function (vm, pos, level)
    return findAtPos(vm.results, pos, level)
end
