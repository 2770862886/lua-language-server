local guide = require 'parser.guide'

local m = {}


--- 获取 position 对应的光标位置
---@param lines table
---@param text string
---@param position position
---@return integer
function m.offset(lines, text, position)
    local row    = position.line
    local start  = guide.lineRange(lines, row)
    local offset = utf8.offset(text, position.character + 1, start)
    return offset
end

--- 将光标位置转化为 position
---@alias position table
---@param lines table
---@param text string
---@param offset integer
---@return position
function m.position(lines, text, offset)
    local row, col = guide.positionOf(lines, offset)
    local start    = guide.lineRange(lines, row)
    local ucol     = utf8.len(text, start + 1, start + col, true)
    return {
        line      = row,
        character = ucol,
    }
end

--- 将2个光标位置转化为 range
---@alias range table
---@param lines table
---@param text string
---@param offset1 integer
---@param offset2 integer
function m.range(lines, text, offset1, offset2)
    return {
        start   = m.position(lines, text, offset1),
        ['end'] = m.position(lines, text, offset2),
    }
end

---@alias location table
---@param uri string
---@param range range
---@return location
function m.location(uri, range)
    return {
        uri   = uri,
        range = range,
    }
end

---@alias locationLink table
---@param uri string
---@param range range
---@param selection range
---@param origin range
function m.locationLink(uri, range, selection, origin)
    return {
        targetUri            = uri,
        targetRange          = range,
        targetSelectionRange = selection,
        originSelectionRange = origin,
    }
end

return m
