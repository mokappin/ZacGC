local async = require("@webc/async")
local http = require("@webc/http")

local config = require("./config")
local db = require("./database")

-- create global state
local global_state = {
    config = (config.read() :: any):unwrap(),
}

_G.state = global_state

-- spawn database
async.on(function()
    db.spawn_db(global_state.config.database)
    db.tables()
    return nil
end)

-- start server
http.run(function(proc)
    proc.split("./server.luau", { port = global_state.config.port })
end)
