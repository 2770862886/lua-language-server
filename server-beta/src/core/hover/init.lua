local files     = require 'files'
local guide     = require 'parser.guide'
local vm        = require 'vm'
local getLabel  = require 'core.hover.label'

local function getHoverAsFunction(source)
    local uri = guide.getRoot(source).uri
    local text = files.getText(uri)
    local values = vm.getValue(source)
    local labels = {}
    for _, value in ipairs(values) do
        if value.type == 'function' then
            labels[#labels+1] = getLabel(value.source)
        end
    end

    local label = table.concat(labels, '\n')
    return {
        label = label,
    }
end

local function getHover(source)
    local isFunction = vm.hasType(source, 'function')
    if isFunction then
        return getHoverAsFunction(source)
    end
end

return function (uri, offset)
    local ast = files.getAst(uri)
    if not ast then
        return nil
    end
    local hover = guide.eachSourceContain(ast.ast, offset, function (source)
        if source.type == 'local'
        or source.type == 'setlocal'
        or source.type == 'getlocal'
        or source.type == 'setglobal'
        or source.type == 'getglobal'
        or source.type == 'field'
        or source.type == 'method' then
            return getHover(source)
        end
    end)
    return hover
end
