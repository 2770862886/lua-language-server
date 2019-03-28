local function solveDiagnostic(lsp, uri, data, callback)
    if data.code then
        callback {
            title = ('禁用诊断(%s)'):format(data.code),
            kind = 'quickfix',
            diagnostics = {data},
            command = {
                title = '禁用诊断',
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
    if data.code == 'undefined-global' then
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
        callback {
            title = ('标记 `%s` 为已定义的全局变量'):format(name),
            kind = 'quickfix',
            diagnostics = {data},
            command = {
                title = '标记全局变量',
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
end

return function (lsp, params)
    local uri = params.textDocument.uri

    local results = {}

    for _, data in ipairs(params.context.diagnostics) do
        solveDiagnostic(lsp, uri, data, function (result)
            results[#results+1] = result
        end)
    end

    if #results == 0 then
        return nil
    end

    return results
end
