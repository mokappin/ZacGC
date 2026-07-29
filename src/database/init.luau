local ccfg = require("@webc/sql_common")
local psql = require("@webc/psql")
local redis = require("@webc/redis")

local friends = require("@self/friends")
local ip_bans = require("@self/ip_bans")
local notifs = require("@self/notifications")
local pastes = require("@self/pastes")
local users = require("@self/users")

local init = {}

function init.spawn_db(cfg: ccfg.CommonConfig): ()
    psql.spawn(cfg)
    redis.spawn()
end

function init.tables(): ()
    users.create_table()
    pastes.create_table()
    friends.create_table()
    notifs.create_table()
    ip_bans.create_table()
end

return init
