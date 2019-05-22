local lang = require 'language'
local library = require 'core.library'

local function disableDiagnostic(lsp, uri, data, callback)
    callback {
        title = lang.script('ACTION_DISABLE_DIAG', data.code),
        kind = 'quickfix',
        command = {
            title = lang.script.COMMAND_DISABLE_DIAG,
            command = 'config',
            arguments = {
                {
                    key = {'diagnostics', 'disable'},
                    action = 'add',
                    value = data.code,
                }
            }
        }
    }
end

local function addGlobal(name, callback)
    callback {
        title = lang.script('ACTION_MARK_GLOBAL', name),
        kind = 'quickfix',
        command = {
            title = lang.script.COMMAND_MARK_GLOBAL,
            command = 'config',
            arguments = {
                {
                    key = {'diagnostics', 'globals'},
                    action = 'add',
                    value = name,
                }
            }
        },
    }
end

local function changeVersion(version, callback)
    callback {
        title = lang.script('ACTION_RUNTIME_VERSION', version),
        kind = 'quickfix',
        command = {
            title = lang.script.COMMAND_RUNTIME_VERSION,
            command = 'config',
            arguments = {
                {
                    key = {'runtime', 'version'},
                    action = 'set',
                    value = version,
                }
            }
        },
    }
end

local function openCustomLibrary(libName, callback)
    callback {
        title = lang.script('ACTION_OPEN_LIBRARY', libName),
        kind = 'quickfix',
        command = {
            title = lang.script.COMMAND_OPEN_LIBRARY,
            command = 'config',
            arguments = {
                {
                    key = {'runtime', 'library'},
                    action = 'add',
                    value = libName,
                }
            }
        },
    }
end

local function solveUndefinedGlobal(lsp, uri, data, callback)
    local vm, lines, text = lsp:getVM(uri)
    if not vm then
        return
    end
    local start = lines:position(data.range.start.line + 1, data.range.start.character + 1)
    local finish = lines:position(data.range['end'].line + 1, data.range['end'].character)
    local name = text:sub(start, finish)
    if #name < 0 or name:find('[^%w_]') then
        return
    end
    addGlobal(name, callback)
    local otherVersion = library.other[name]
    if otherVersion then
        for _, version in ipairs(otherVersion) do
            changeVersion(version, callback)
        end
    end

    local customLibrary = library.custom[name]
    if customLibrary then
        for _, libName in ipairs(customLibrary) do
            openCustomLibrary(libName, callback)
        end
    end
end

local function solveLowercaseGlobal(lsp, uri, data, callback)
    local vm, lines, text = lsp:getVM(uri)
    if not vm then
        return
    end
    local start = lines:position(data.range.start.line + 1, data.range.start.character + 1)
    local finish = lines:position(data.range['end'].line + 1, data.range['end'].character)
    local name = text:sub(start, finish)
    if #name < 0 or name:find('[^%w_]') then
        return
    end
    addGlobal(name, callback)
end

local function solveTrailingSpace(lsp, uri, data, callback)
    callback {
        title = lang.script.ACTION_REMOVE_SPACE,
        kind = 'quickfix',
        command = {
            title = lang.script.COMMAND_REMOVE_SPACE,
            command = 'removeSpace',
            arguments = {
                {
                    uri = uri,
                }
            }
        },
    }
end

local function solveNewlineCall(lsp, uri, data, callback)
    callback {
        title = lang.script.ACTION_ADD_SEMICOLON,
        kind = 'quickfix',
        edit = {
            changes = {
                [uri] = {
                    {
                        range = {
                            start = data.range.start,
                            ['end'] = data.range.start,
                        },
                        newText = ';',
                    }
                }
            }
        }
    }
end

local function solveAmbiguity1(lsp, uri, data, callback)
    callback {
        title = lang.script.ACTION_ADD_BRACKETS,
        kind = 'quickfix',
        command = {
            title = lang.script.COMMAND_ADD_BRACKETS,
            command = 'solve',
            arguments = {
                {
                    name = 'ambiguity-1',
                    uri = uri,
                    range = data.range,
                }
            }
        },
    }
end

local function findSyntax(astErr, lines, data)
    local start = lines:position(data.range.start.line + 1, data.range.start.character + 1)
    local finish = lines:position(data.range['end'].line + 1, data.range['end'].character)
    for _, err in ipairs(astErr) do
        if err.start == start and err.finish == finish then
            return err
        end
    end
    return nil
end

local function solveSyntaxByChangeVersion(err, callback)
    if type(err.version) == 'table' then
        for _, version in ipairs(err.version) do
            changeVersion(version, callback)
        end
    else
        changeVersion(err.version, callback)
    end
end

local function solveSyntaxByAddDoEnd(uri, data, callback)
    callback {
        title = lang.script.ACTION_ADD_DO_END,
        kind = 'quickfix',
        edit = {
            changes = {
                [uri] = {
                    {
                        range = {
                            start = data.range.start,
                            ['end'] = data.range.start,
                        },
                        newText = 'do ',
                    },
                    {
                        range = {
                            start = data.range['end'],
                            ['end'] = data.range['end'],
                        },
                        newText = ' end',
                    }
                }
            }
        }
    }
end

local function solveSyntax(lsp, uri, data, callback)
    local obj = lsp:getFile(uri)
    if not obj then
        return
    end
    local astErr, lines = obj.astErr, obj.lines
    if not astErr or not lines then
        return
    end
    local err = findSyntax(astErr, lines, data)
    if not err then
        return nil
    end
    if err.version then
        solveSyntaxByChangeVersion(err, callback)
    end
    if err.type == 'ACTION_AFTER_BREAK' or err.type == 'ACTION_AFTER_RETURN' then
        solveSyntaxByAddDoEnd(uri, data, callback)
    end
end

local function solveDiagnostic(lsp, uri, data, callback)
    if data.source == lang.script.DIAG_SYNTAX_CHECK then
        solveSyntax(lsp, uri, data, callback)
    end
    if not data.code then
        return
    end
    if data.code == 'undefined-global' then
        solveUndefinedGlobal(lsp, uri, data, callback)
    end
    if data.code == 'trailing-space' then
        solveTrailingSpace(lsp, uri, data, callback)
    end
    if data.code == 'newline-call' then
        solveNewlineCall(lsp, uri, data, callback)
    end
    if data.code == 'ambiguity-1' then
        solveAmbiguity1(lsp, uri, data, callback)
    end
    if data.code == 'lowercase-global' then
        solveLowercaseGlobal(lsp, uri, data, callback)
    end
    disableDiagnostic(lsp, uri, data, callback)
end

return function (lsp, uri, diagnostics)
    local results = {}

    for _, data in ipairs(diagnostics) do
        solveDiagnostic(lsp, uri, data, function (result)
            results[#results+1] = result
        end)
    end

    return results
end
