local http = require("@webc/http")
local json = require("@webc/json")

local _users = require("../../database/users")
local general = require("../../general")
local helpers = require("./helpers")
local ip_ban = require("../../model/ip_ban")
local ip_bans = require("../../database/ip_bans")
local user = require("../../model/user")

local mod = {}

type CreateIPBan = {
    ip: string,
    reason: string,
}

function mod.create_request(p, h, c, b: http.Body): http.Response
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    if user.banned then
        return helpers.api_return(false, general.error_msg(general.error("NotAllowed", nil)), nil)
    end

    -- ...
    local fail_reason = ""
    local ok, req: CreateIPBan = xpcall(function()
        return json.deserialize_validated(b:as_string(), {
            reason = {
                options = {
                    String = {
                        min_length = 1,
                        max_length = 1024,
                    },
                },
                required = true,
            },
        })
    end, function(e: string)
        fail_reason = tostring(e)
    end)

    if not ok then
        return helpers.api_return(false, general.error_msg(general.error("General", fail_reason:split("\n")[1])), nil)
    end

    -- create ip ban
    local res = ip_bans.create_ip_ban(ip_ban.new(user.id, req.ip, req.reason))

    if res.is_ok then
        return helpers.api_return(true, "Success", res:unwrap())
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

function mod.delete_request(p: { ip: string }, _, c): http.Response
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    -- return
    local res = ip_bans.delete_ip_ban_by_ip(p.ip, user)

    if res.is_ok then
        return helpers.api_return(true, "Success", nil)
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

return mod
