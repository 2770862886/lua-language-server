local matcher    = require 'matcher'
local parser     = require 'parser'

rawset(_G, 'TEST', true)

function TEST(fullkey)
    return function (script)
        local start  = script:find('<?', 1, true)
        local finish = script:find('?>', 1, true)
        local pos = (start + finish) // 2 + 1
        local new_script = script:gsub('<[!?]', '  '):gsub('[!?]>', '  ')
        local ast = parser:ast(new_script)
        assert(ast)
        local results = matcher.compile(ast)
        assert(results)
        local result = matcher.findResult(results, pos)
        assert(result)
        assert(result.type == 'var')
        local var = result.var
        assert(var)
        local _, name = matcher.findLib(var)
        assert(name == fullkey)
    end
end

TEST 'require' [[
<?require?> 'xxx'
]]

TEST 'require' [[
local <?req?> = require
]]

TEST 'require' [[
local req = require
local t = {
    xx = req,
}
t[<?'xx'?>]()
]]

TEST 'table' [[
<?table?>.unpack()
]]

TEST 'table' [[
local <?xx?> = require 'table'
]]

TEST 'table' [[
local rq = require
local lib = 'table'
local <?xx?> = rq(lib)
]]

TEST 'table.insert' [[
table.<?insert?>()
]]

TEST 'table.insert' [[
local t = table
t.<?insert?>()
]]

TEST 'table.insert' [[
local insert = table.insert
<?insert?>()
]]

TEST 'table.insert' [[
local t = require 'table'
t.<?insert?>()
]]

TEST 'table.insert' [[
require 'table'.<?insert?>()
]]

TEST '*string:sub' [[
local str = 'xxx'
str.<?sub?>()
]]

TEST '*string:sub' [[
local str = 'xxx'
str:<?sub?>(1, 1)
]]

TEST '*string:sub' [[
('xxx').<?sub?>()
]]

TEST 'bee::filesystem' [[
local <?fs?> = require 'bee.filesystem'
]]

TEST 'fs.current_path' [[
local filesystem = require 'bee.filesystem'

ROOT = filesystem.<?current_path?>()
]]

TEST(nil)[[
print(<?insert?>)
]]
