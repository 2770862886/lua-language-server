local thread = require 'bee.thread'
local errlog = thread.channel 'errlog'
local taskId = 0
local idlePool = {}
local runningList = {}

local function createTask()
    taskId = taskId + 1
    local id = taskId
    local requestName  = 'request'  .. tostring(id)
    local responseName = 'response' .. tostring(id)
    thread.newchannel(requestName)
    thread.newchannel(responseName)
    local buf = ([[
package.cpath  = %q
package.path   = %q
local thread   = require 'bee.thread'
local request  = thread.channel(%q)
local response = thread.channel(%q)
local errlog   = thread.channel 'errlog'

local function task()
    local dump, arg = request:bpop()
    local env = setmetatable({
        IN  = request,
        OUT = response,
        ERR = errlog,
    }, { __index = _ENV })
    local f, err = load(dump, '=task', 't', env)
    if not f then
        errlog:push(err)
        return
    end
    local result = f(arg)
    response:push(result)
end

while true do
    local ok, result = xpcall(task, debug.traceback)
    if not ok then
        errlog:push(result)
    end
end
]]):format(package.cpath, package.path, requestName, responseName)
    log.debug('Create thread, id: ', id)
    return {
        id       = id,
        thread   = thread.thread(buf),
        request  = thread.channel(requestName),
        response = thread.channel(responseName),
    }
end

local function run(name, arg, callback)
    local dump = io.load(ROOT / 'src' / 'async' / (name .. '.lua'))
    if not dump then
        error(('找不到[%s]'):format(name))
    end
    local task = table.remove(idlePool)
    if not task then
        task = createTask()
    end
    runningList[task.id] = {
        task     = task,
        callback = callback,
    }
    task.request:push(dump, arg)
    -- TODO 线程回收后禁止外部再使用通道
    return task.request, task.response
end

local function onTick()
    local ok, msg = errlog:pop()
    if ok then
        log.error(msg)
    end
    for id, running in pairs(runningList) do
        if running.callback then
            local ok, result = running.task.response:pop()
            if ok then
                runningList[id] = nil
                idlePool[#idlePool+1] = running.task
                xpcall(running.callback, log.error, result)
            end
        end
    end
end

return {
    onTick = onTick,
    run    = run,
}
