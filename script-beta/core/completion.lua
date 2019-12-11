local ckind    = require 'define.CompletionItemKind'
local files    = require 'files'
local guide    = require 'parser.guide'
local matchKey = require 'core.matchKey'
local vm       = require 'vm'
local library  = require 'library'
local getLabel = require 'core.hover.label'
local getName  = require 'core.hover.name'
local getArg   = require 'core.hover.arg'
local getDesc  = require 'core.hover.description'
local getHover = require 'core.hover'
local config   = require 'config'
local util     = require 'utility'
local markdown = require 'provider.markdown'

local stackID = 0
local stacks = {}
local function stack(callback)
    stackID = stackID + 1
    stacks[stackID] = callback
    return stackID
end

local function clearStack()
    stacks = {}
end

local function resolveStack(id)
    local callback = stacks[id]
    if not callback then
        return nil
    end
    return callback()
end

local function isSpace(char)
    if char == ' '
    or char == '\n'
    or char == '\r'
    or char == '\t' then
        return true
    end
    return false
end

local function skipSpace(text, offset)
    for i = offset, 1, -1 do
        local char = text:sub(i, i)
        if not isSpace(char) then
            return i
        end
    end
    return 0
end

local function findWord(text, offset)
    for i = offset, 1, -1 do
        if not text:sub(i, i):match '[%w_]' then
            if i == offset then
                return nil
            end
            return text:sub(i+1, offset), i+1
        end
    end
    return text:sub(1, offset), 1
end

local function findSymbol(text, offset)
    for i = offset, 1, -1 do
        local char = text:sub(i, i)
        if isSpace(char) then
            goto CONTINUE
        end
        if char == '.'
        or char == ':'
        or char == '#' then
            return char, i
        end
        ::CONTINUE::
    end
    return nil
end

local function findAnyPos(text, offset)
    for i = offset, 1, -1 do
        if not isSpace(text:sub(i, i)) then
            return i
        end
    end
    return nil
end

local function findParent(ast, text, offset)
    for i = offset, 1, -1 do
        local char = text:sub(i, i)
        if isSpace(char) then
            goto CONTINUE
        end
        local oop
        if char == '.' then
            oop = false
        elseif char == ':' then
            oop = true
        else
            return nil, nil
        end
        local anyPos = findAnyPos(text, i-1)
        if not anyPos then
            return nil, nil
        end
        local parent = guide.eachSourceContain(ast.ast, anyPos, function (source)
            if source.finish == anyPos then
                return source
            end
        end)
        if parent then
            return parent, oop
        end
        ::CONTINUE::
    end
    return nil, nil
end

local function buildFunctionSnip(source)
    local name = getName(source):gsub('^.-[$.:]', '')
    local args = vm.eachDef(source, function (info)
        if info.source.type == 'function' then
            local args = getArg(info.source)
            if args ~= '' then
                return args
            end
        end
    end) or ''
    local id = 0
    args = args:gsub('[^,]+', function (arg)
        id = id + 1
        return arg:gsub('^(%s*)(.+)', function (sp, word)
            return ('%s${%d:%s}'):format(sp, id, word)
        end)
    end)
    return ('%s(%s)'):format(name, args)
end

local function buildDetail(source)
    local types = vm.getType(source)
    return types
end

local function buildDesc(source)
    local hover = getHover.get(source)
    local md = markdown()
    md:add('lua', hover.label)
    md:add('md',  hover.description)
    return md:string()
end

local function buildFunction(results, source, oop, data)
    local snipType = config.config.completion.callSnippet
    if snipType == 'Disable' or snipType == 'Both' then
        results[#results+1] = data
    end
    if snipType == 'Both' or snipType == 'Replace' then
        local snipData = util.deepCopy(data)
        snipData.kind = ckind.Snippet
        snipData.label = snipData.label .. '()'
        snipData.insertText = buildFunctionSnip(source)
        snipData.insertTextFormat = 2
        snipData.id  = stack(function ()
            return {
                detail      = buildDetail(source),
                description = buildDesc(source),
            }
        end)
        results[#results+1] = snipData
    end
end

local function checkLocal(ast, word, offset, results)
    local locals = guide.getVisibleLocals(ast.ast, offset)
    for name, source in pairs(locals) do
        if matchKey(word, name) then
            if vm.hasType(source, 'function') then
                buildFunction(results, source, false, {
                    label  = name,
                    kind   = ckind.Function,
                    id     = stack(function ()
                        return {
                            detail      = buildDetail(source),
                            description = buildDesc(source),
                        }
                    end),
                })
            else
                results[#results+1] = {
                    label  = name,
                    kind   = ckind.Variable,
                    id     = stack(function ()
                        return {
                            detail      = buildDetail(source),
                            description = buildDesc(source),
                        }
                    end),
                }
            end
        end
    end
end

local function isSameSource(source, pos)
    return source.start <= pos and source.finish >= pos
end

local function checkField(word, start, parent, oop, results)
    local used = {}
    vm.eachField(parent, function (info)
        local key = info.key
        if not key or key:sub(1, 1) ~= 's' then
            return
        end
        if isSameSource(info.source, start) then
            return
        end
        local name = key:sub(3)
        if used[name] then
            return
        end
        if not matchKey(word, name) then
            used[name] = true
            return
        end
        local kind = ckind.Field
        if vm.hasType(info.source, 'function') then
            if oop then
                kind = ckind.Method
            else
                kind = ckind.Function
            end
            used[name] = true
            buildFunction(results, info.source, oop, {
                label = name,
                kind  = kind,
                id    = stack(function ()
                    return {
                        detail      = buildDetail(info.source),
                        description = buildDesc(info.source),
                    }
                end),
            })
        else
            if oop then
                return
            end
            used[name] = true
            local literal = vm.getLiteral(info.source)
            if literal ~= nil then
                kind = ckind.Enum
            end
            results[#results+1] = {
                label = name,
                kind  = kind,
                id    = stack(function ()
                    return {
                        detail      = buildDetail(info.source),
                        description = buildDesc(info.source),
                    }
                end)
            }
        end
    end)
    return used
end

local function checkCommon(word, text, results)
    local used = {}
    for _, result in ipairs(results) do
        used[result.label] = true
    end
    for str in text:gmatch '[%a_][%w_]*' do
        if not used[str] and str ~= word then
            used[str] = true
            if matchKey(word, str) then
                results[#results+1] = {
                    label = str,
                    kind  = ckind.Text,
                }
            end
        end
    end
end

local function isInString(ast, offset)
    return guide.eachSourceContain(ast.ast, offset, function (source)
        if source.type == 'string' then
            return true
        end
    end)
end

local keyWordMap = {
{'do', function (ast, text, start, results)
    if config.config.completion.keywordSnippet then
        results[#results+1] = {
            label = 'do .. end',
            kind  = ckind.Snippet,
            insertTextFormat = 2,
            insertText = [[
do
    $0
end]],
        }
    end
    return guide.eachSourceContain(ast.ast, start, function (source)
        if source.type == 'while'
        or source.type == 'in'
        or source.type == 'loop' then
            for i = 1, #source.keyword do
                if start == source.keyword[i] then
                    return true
                end
            end
        end
    end)
end},
{'and'},
{'break'},
{'else'},
{'elseif', function (ast, text, start, results)
    if config.config.completion.keywordSnippet then
        results[#results+1] = {
            label = 'elseif .. then',
            kind  = ckind.Snippet,
            insertTextFormat = 2,
            insertText = [[elseif $1 then]],
        }
    end
end},
{'end'},
{'false'},
{'for', function (ast, text, start, results)
    if config.config.completion.keywordSnippet then
        results[#results+1] = {
            label = 'for .. in',
            kind  = ckind.Snippet,
            insertTextFormat = 2,
            insertText = [[
for ${1:key, value} in ${2:pairs(${3:t})} do
    $0
end]]
        }
        results[#results+1] = {
            label = 'for i = ..',
            kind  = ckind.Snippet,
            insertTextFormat = 2,
            insertText = [[
for ${1:i} = ${2:1}, ${3:10, 1} do
    $0
end]]
        }
    end
end},
{'function', function (ast, text, start, results)
    if config.config.completion.keywordSnippet then
        results[#results+1] = {
            label = 'function ()',
            kind  = ckind.Snippet,
            insertTextFormat = 2,
            insertText = [[
function $1($2)
    $0
end]]
        }
    end
end},
{'goto'},
{'if', function (ast, text, start, results)
    if config.config.completion.keywordSnippet then
        results[#results+1] = {
            label = 'if .. then',
            kind  = ckind.Snippet,
            insertTextFormat = 2,
            insertText = [[
if $1 then
    $0
end]]
        }
    end
end},
{'in', function (ast, text, start, results)
    if config.config.completion.keywordSnippet then
        results[#results+1] = {
            label = 'in ..',
            kind  = ckind.Snippet,
            insertTextFormat = 2,
            insertText = [[
in ${1:pairs(${2:t})} do
    $0
end]]
        }
    end
end},
{'local', function (ast, text, start, results)
    if config.config.completion.keywordSnippet then
        results[#results+1] = {
            label = 'local function',
            kind  = ckind.Snippet,
            insertTextFormat = 2,
            insertText = [[
local function $1($2)
    $0
end]]
        }
    end
end},
{'nil'},
{'not'},
{'or'},
{'repeat', function (ast, text, start, results)
    if config.config.completion.keywordSnippet then
        results[#results+1] = {
            label = 'repeat .. until',
            kind  = ckind.Snippet,
            insertTextFormat = 2,
            insertText = [[
repeat
    $0
until $1]]
        }
    end
end},
{'return', function (ast, text, start, results)
    if config.config.completion.keywordSnippet then
        results[#results+1] = {
            label = 'do return end',
            kind  = ckind.Snippet,
            insertTextFormat = 2,
            insertText = [[do return $1end]]
        }
    end
end},
{'then'},
{'true'},
{'until'},
{'while', function (ast, text, start, results)
    if config.config.completion.keywordSnippet then
        results[#results+1] = {
            label = 'while .. do',
            kind  = ckind.Snippet,
            insertTextFormat = 2,
            insertText = [[
while ${1:true} do
    $0
end]]
        }
    end
end},
}

local function checkKeyWord(ast, text, start, word, results)
    for _, data in ipairs(keyWordMap) do
        local key = data[1]
        if matchKey(word, key) then
            results[#results+1] = {
                label = key,
                kind  = ckind.Keyword,
            }
            local func = data[2]
            if func then
                local stop = func(ast, text, start, results)
                if stop then
                    return true
                end
            end
        end
    end
end

local function checkDot(ast, start, results)

end

local function tryWord(ast, text, offset, results)
    local word, start = findWord(text, offset)
    if not word then
        return nil
    end
    if not isInString(ast, offset) then
        local parent, oop = findParent(ast, text, start - 1)
        if parent then
            checkField(word, start, parent, oop, results)
        else
            local stop = checkKeyWord(ast, text, start, word, results)
            if stop then
                return
            end
            checkLocal(ast, word, start, results)
            local env = guide.getLocal(ast.ast, '_ENV', start)
            checkField(word, start, env, false, results)
        end
    end
    checkCommon(word, text, results)
end

local function trySymbol(ast, text, offset, results)
    local symbol, start = findSymbol(text, offset)
    if not symbol then
        return nil
    end
    if isInString(ast, offset) then
        return nil
    end
    if symbol == '.' then
        checkDot(ast, start, results)
    end
end

local function completion(uri, offset)
    local ast = files.getAst(uri)
    if not ast then
        return nil
    end
    clearStack()
    local text = files.getText(uri)
    local results = {}

    tryWord(ast, text, offset, results)
    trySymbol(ast, text, offset, results)

    if #results == 0 then
        return nil
    end
    return results
end

local function resolve(id)
    return resolveStack(id)
end

return {
    completion = completion,
    resolve    = resolve,
}
