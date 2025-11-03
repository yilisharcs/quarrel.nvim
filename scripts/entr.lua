-- Live inspect the arglist database
vim.g.quarrel = { database = arg[1] }
package.path = "./lua/?.lua" .. ";" .. "./lua/?/init.lua" .. package.path
local arglist, err = require("quarrel")._get_arglist_database()
if err then
        print(err)
else
        local json = vim.json.encode(arglist, { indent = "    " })
        print(json)
end
