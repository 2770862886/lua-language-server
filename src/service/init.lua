local sleep = require 'ffi.sleep'
local ext   = require 'process.ext'
local lsp   = require 'lsp'

local Method = {}

function Method.initialize()
    return {
        capabilities = {
            definitionProvider = true,
        }
    }
end

local function listen(self, input, output)
    if input then
        log.info('指定输入文件，路径为：', input)
        fs.create_directories(input:parent_path())
        io.input(io.open(input:string(), 'rb'))
    else
        ext.set_filemode(io.stdin, 'b')
    end
    if output then
        log.info('指定输出文件，路径为：', output)
        fs.create_directories(output:parent_path())
        io.output(io.open(output:string(), 'wb'))
    else
        ext.set_filemode(io.stdout, 'b')
        io.stdout:setvbuf 'no'
    end

    local session = lsp()
    session:setInput(function (mode)
        return io.read(mode)
    end)
    session:setOutput(function (buf)
        io.write(buf)
        log.debug(buf)
    end)
    session:start(function (method, params)
        local f = Method[method]
        if f then
            return f(params)
        end
        return nil
    end)
end

local mt = {
    definition = require 'service.definition',
    listen     = listen,
}
mt.__index = mt

return function ()
    local session = setmetatable({}, mt)
    return session
end
