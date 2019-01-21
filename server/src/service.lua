local subprocess = require 'bee.subprocess'
local method     = require 'method'
local thread     = require 'bee.thread'
local async      = require 'async'
local rpc        = require 'rpc'
local parser     = require 'parser'
local core    = require 'core'
local lang       = require 'language'

thread.newchannel 'proto'

local ErrorCodes = {
    -- Defined by JSON RPC
    ParseError           = -32700,
    InvalidRequest       = -32600,
    MethodNotFound       = -32601,
    InvalidParams        = -32602,
    InternalError        = -32603,
    serverErrorStart     = -32099,
    serverErrorEnd       = -32000,
    ServerNotInitialized = -32002,
    UnknownErrorCode     = -32001,

    -- Defined by the protocol.
    RequestCancelled     = -32800,
}

local mt = {}
mt.__index = mt

function mt:_callMethod(name, params)
    local optional
    if name:sub(1, 2) == '$/' then
        name = name:sub(3)
        optional = true
    end
    local f = method[name]
    if f then
        local clock = os.clock()
        local suc, res = xpcall(f, debug.traceback, self, params)
        local passed = os.clock() - clock
        if passed > 0.1 then
            log.debug(('Task [%s] takes [%.3f]sec.'):format(name, passed))
        end
        if suc then
            return res
        else
            local ok, r = pcall(table.dump, params)
            local dump = ok and r or 'Cyclic table'
            log.debug(('Task [%s] failed, params: %s'):format(
                name, dump
            ))
            log.debug(res)
            return nil, {
                code = ErrorCodes.InternalError,
                message = r .. '\n' .. res,
            }
        end
    end
    if optional then
        return nil
    else
        return nil, {
            code = ErrorCodes.MethodNotFound,
            message = 'MethodNotFound',
        }
    end
end

function mt:_doProto(proto)
    local id     = proto.id
    local name   = proto.method
    local params = proto.params
    local response, err = self:_callMethod(name, params)
    if not id then
        return
    end
    local container = table.container()
    if err then
        container.error = err
    else
        container.result = response
    end
    rpc:response(id, container)
end

function mt:clearDiagnostics(uri)
    rpc:notify('textDocument/publishDiagnostics', {
        uri = uri,
        diagnostics = {},
    })
end

function mt:read(mode)
    if not self._input then
        return nil
    end
    return self._input(mode)
end

function mt:needCompile(uri, compiled)
    if self._needCompile[uri] then
        return
    end
    if not compiled then
        compiled = {}
    end
    if compiled[uri] then
        return
    end
    self._needCompile[uri] = compiled
    table.insert(self._needCompile, 1, uri)
end

function mt:saveText(uri, version, text)
    local obj = self._file[uri]
    if obj then
        obj.version = version
        obj.text = text
        self:needCompile(uri)
    else
        self._file[uri] = {
            version = version,
            text = text,
        }
        self:needCompile(uri)
    end
end

function mt:readText(uri, path)
    local obj = self._file[uri]
    if obj then
        return
    end
    local text = io.load(path)
    if not text then
        return
    end
    self._file[uri] = {
        version = -1,
        text = text,
    }
    self:needCompile(uri)
end

function mt:removeText(uri)
    local obj = self._file[uri]
    if obj then
        return
    end
    obj.version = -1
end

function mt:reCompile()
    local compiled = {}
    for uri in pairs(self._file) do
        self:needCompile(uri, compiled)
    end

    if self._needShowComplete then
        self._needShowComplete = nil
        rpc:notify('window/showMessage', {
            type = 3,
            message = lang.script.MWS_COMPLETE,
        })
    end
end

function mt:loadVM(uri)
    local obj = self._file[uri]
    if not obj then
        return nil
    end
    self:compileVM(uri)
    return obj.vm, obj.lines, obj.text
end

function mt:_markCompiled(uri)
    local compiled = self._needCompile[uri]
    if compiled then
        compiled[uri] = true
        self._needCompile[uri] = nil
    end
    for i, u in ipairs(self._needCompile) do
        if u == uri then
            table.remove(self._needCompile, i)
            break
        end
    end
    return compiled
end

function mt:compileAst(obj)
    local ast, err = parser:ast(obj.text)
    obj.astErr = err
    if not ast then
        if type(err) == 'string' then
            local message = lang.script('PARSER_CRASH', err)
            log.debug(message)
            rpc:notify('window/showMessage', {
                type = 3,
                message = lang.script('PARSER_CRASH', err:match 'grammar%.lua%:%d+%:(.+)'),
            })
        end
    end
    return ast
end

function mt:_clearChainNode(obj, uri)
    if obj.parent then
        for pUri in pairs(obj.parent) do
            local parent = self._file[pUri]
            if parent and parent.child then
                parent.child[uri] = nil
            end
        end
    end
end

function mt:_compileChain(obj, compiled)
    if not obj.child then
        return
    end
    if not compiled then
        compiled = {}
    end
    local list = {}
    for child in pairs(obj.child) do
        list[#list+1] = child
    end
    table.sort(list)
    for _, child in ipairs(list) do
        self:needCompile(child, compiled)
    end
end

function mt:compileVM(uri)
    local obj = self._file[uri]
    if not obj then
        return nil
    end
    if not self._needCompile[uri] then
        return nil
    end

    local compiled = self:_markCompiled(uri)
    local clock = os.clock()
    local ast = self:compileAst(obj)
    obj.astCost = os.clock() - clock
    self:_clearChainNode(obj, uri)

    local clock = os.clock()
    obj.vm = core.vm(ast, self, uri)
    obj.vmCost = os.clock() - clock

    local clock = os.clock()
    obj.lines = parser:lines(obj.text, 'utf8')
    obj.lineCost = os.clock() - clock

    if not obj.vm then
        return obj
    end

    self:_compileChain(obj, compiled)

    return obj
end

function mt:doDiagnostics(uri)
    local name = 'textDocument/publishDiagnostics'
    local vm, lines = self:getVM(uri)
    if not vm then
        self:clearDiagnostics(uri)
        return
    end
    local data = {
        uri   = uri,
        vm    = vm,
        lines = lines,
    }
    local res  = self:_callMethod(name, data)
    if res then
        rpc:notify(name, {
            uri = uri,
            diagnostics = res,
        })
    end
end

function mt:getVM(uri)
    local obj = self._file[uri]
    if not obj then
        return nil
    end
    return obj.vm, obj.lines, obj.text
end

function mt:getAstErrors(uri)
    local obj = self._file[uri]
    if not obj then
        return nil
    end
    return obj.astErr
end

function mt:compileChain(child, parent)
    local parentObj = self._file[parent]
    local childObj = self._file[child]

    if not parentObj or not childObj then
        return
    end
    if parentObj == childObj then
        return
    end

    if not parentObj.child then
        parentObj.child = {}
    end
    parentObj.child[child] = true

    if not childObj.parent then
        childObj.parent = {}
    end
    childObj.parent[parent] = true
end

function mt:checkWorkSpaceComplete()
    if self._hasCheckedWorkSpaceComplete then
        return
    end
    self._hasCheckedWorkSpaceComplete = true
    if self.workspace:isComplete() then
        return
    end
    self._needShowComplete = true
    rpc:notify('window/showMessage', {
        type = 3,
        message = lang.script.MWS_NOT_COMPLETE,
    })
end

function mt:_createCompileTask()
    local uri = self._needCompile[1]
    if not uri then
        return nil
    end
    self._compileTask = coroutine.create(function ()
        self:compileVM(uri)
        self:doDiagnostics(uri)
    end)
end

function mt:_doCompileTask()
    if not self._compileTask then
        self:_createCompileTask()
    end
    if not self._compileTask then
        return
    end
    while true do
        local suc, res = coroutine.resume(self._compileTask)
        if not suc then
            break
        end
        if coroutine.status(self._compileTask) == 'suspended' then
            self:_loadProto()
        else
            self._compileTask = nil
            return
        end
    end
end

function mt:_loadProto()
    while true do
        local ok, proto = self._proto:pop()
        if not ok then
            break
        end
        if proto.method then
            self:_doProto(proto)
        else
            rpc:recieve(proto)
        end
    end
end

function mt:onTick()
    self:_loadProto()
    self:_doCompileTask()

    if os.clock() - self._clock >= 600 then
        self._clock = os.clock()
        local count = 0
        for _ in pairs(self._file) do
            count = count + 1
        end
        local mem = collectgarbage 'count'
        log.debug(('\n\z
        State\n\z
        Mem:   [%.3f]kb\n\z
        Cache: [%d]'):format(
            mem,
            count
        ))
    end
end

function mt:listen()
    subprocess.filemode(io.stdin, 'b')
    subprocess.filemode(io.stdout, 'b')
    io.stdin:setvbuf 'no'
    io.stdout:setvbuf 'no'

    self._proto = thread.channel 'proto'

    async.call([[require 'proto']])

    while true do
        async.onTick()
        self:onTick()
        thread.sleep(0.001)
    end
end

return function ()
    local session = setmetatable({
        _file = {},
        _needCompile = {},
        _clock = -100,
        _version = 0,
    }, mt)
    return session
end
