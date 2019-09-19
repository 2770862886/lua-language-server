local thread = require 'bee.thread'

local m = {}
m.type = 'pub.brave'

--- 注册成为勇者
function m:register(id)
    self.taskpad = thread.channel('taskpad' .. id)
    self.waiter  = thread.channel('waiter'  .. id)
end
