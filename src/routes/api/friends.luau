local http = require("@webc/http")

local friends = require("../../database/friends")
local friendship = require("../../model/friends")
local general = require("../../general")
local helpers = require("./helpers")
local notification = require("../../model/notification")
local notifs = require("../../database/notifications")
local user = require("../../model/user")
local users = require("../../database/users")

local mod = {}

function mod.create_request(p: { ["other_user"]: string }, h, c): http.Response
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    if user.banned then
        return helpers.api_return(false, general.error_msg(general.error("NotAllowed", nil)), nil)
    end

    -- create friendship
    local res = friends.create_friendship(friendship.new(user.id, p.other_user, friendship.status("Requested")))

    if res.is_ok then
        return helpers.api_return(true, "Success", res:unwrap())
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

function mod.approve_request(p: { ["other_user"]: string }, h, c): http.Response
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    if user.banned then
        return helpers.api_return(false, general.error_msg(general.error("NotAllowed", nil)), nil)
    end

    -- update friendship
    local res = friends.update_friendship_status(p.other_user, user, friendship.status("Friends"))

    if res.is_ok then
        -- send notif
        local res = res:unwrap()
        local receiver = users.get_user_by_id(res.user2)

        if receiver.is_err then
            return helpers.api_return(false, general.error_msg(receiver:unwrap_err()), nil)
        end

        local receiver = receiver:unwrap()

        notifs.create_notif(
            notification.new(
                res.user1,
                `{receiver.username} has accepted your friend request!`,
                `/@{receiver.username}`
            )
        )

        -- return
        return helpers.api_return(true, "Success", res)
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

function mod.delete_request(p: { other_user: string }, _, c): http.Response
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    -- return
    local res = friends.delete_friendship(p.other_user, user)

    if res.is_ok then
        return helpers.api_return(true, "Success", nil)
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

return mod
