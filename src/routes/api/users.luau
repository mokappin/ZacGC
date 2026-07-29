local array = require("@webc/array")
local http = require("@webc/http")
local json = require("@webc/json")
local tools = require("@webc/tools")

local _ip_bans = require("../../database/ip_bans")
local general = require("../../general")
local helpers = require("./helpers")
local notifs = require("../../database/notifications")
local user = require("../../model/user")
local users = require("../../database/users")

local mod = {}

type CreateUser = {
    username: string,
    password: string,
}

function mod.create_request(_, h, _, b: http.Body): http.Response
    -- validate request
    if b:is_empty() then
        return helpers.api_return(false, general.error_msg(general.error("EmptyBody", nil)), nil)
    end

    local fail_reason = ""
    local ok, req: CreateUser = xpcall(function()
        return json.deserialize_validated(b:as_string(), {
            username = {
                options = {
                    String = {
                        max_length = 32,
                        min_length = 2,
                    },
                },
                required = true,
            },
            password = {
                options = { String = {
                    min_length = 6,
                } },
                required = true,
            },
        })
    end, function(e: string)
        fail_reason = tostring(e)
    end)

    if not ok then
        return helpers.api_return(false, general.error_msg(general.error("General", fail_reason:split("\n")[1])), nil)
    end

    -- !<macros/check_for_ip_ban.macro.luau>

    -- pull ip from headers
    local ip = h[_G.state.config.real_ip_header] or ""

    -- ...
    local ua = user.new(req.username:lower(), req.password)

    -- create first session
    local token = tools.uuid()
    array.push(ua.sessions, { ip = ip, t = tools.sha256(token), ts = ua.created })

    -- create user
    local res = users.create_user(ua)

    if res.is_ok then
        return helpers.api_return_headers(true, "Success", res:unwrap(), {
            ["Set-Cookie"] = `__Secure-pastry-token={token}; SameSite=Lax; Secure; Path=/; HostOnly=true; HttpOnly=true; Max-Age={60 * 60 * 24 * 365}`,
        })
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

type Login = {
    username: string,
    password: string,
}

function mod.login_request(_, h, c, b: http.Body): http.Response
    -- validate request
    if b:is_empty() then
        return helpers.api_return(false, general.error_msg(general.error("EmptyBody", nil)), nil)
    end

    local fail_reason = ""
    local ok, req: Login = xpcall(function()
        return json.deserialize_validated(b:as_string(), {
            username = {
                options = {
                    String = {
                        max_length = 32,
                        min_length = 2,
                    },
                },
                required = true,
            },
            password = {
                options = { String = {
                    min_length = 6,
                } },
                required = true,
            },
        })
    end, function(e: string)
        fail_reason = tostring(e)
    end)

    if not ok then
        return helpers.api_return(false, general.error_msg(general.error("General", fail_reason:split("\n")[1])), nil)
    end

    -- pull ip from headers
    local ip = h[_G.state.config.real_ip_header] or ""

    -- ...
    local ua = users.get_user_by_username(req.username)

    if ua.is_err then
        return helpers.api_return(false, general.error_msg(ua:unwrap_err()), nil)
    end

    local ua = ua:unwrap()

    -- check password
    if tools.sha256(req.password .. ua.salt) ~= ua.password then
        return helpers.api_return(false, general.error_msg(general.error("NotAllowed", nil)), nil)
    end

    -- create session
    local token = tools.uuid()
    array.push(ua.sessions, { ip = ip, t = tools.sha256(token), ts = tools.unix_epoch_timestamp() })

    -- return
    local res = users.update_user_sessions(ua.id, ua.sessions, ua)

    if res.is_ok then
        return helpers.api_return_headers(true, "Success", res:unwrap(), {
            ["Set-Cookie"] = `__Secure-pastry-token={token}; SameSite=Lax; Secure; Path=/; HostOnly=true; HttpOnly=true; Max-Age={60 * 60 * 24 * 365}`,
        })
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

function mod.logout_request(p: { id: string }, h, c, b: http.Body): http.Response
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    return helpers.api_return_headers(true, "Success", nil, {
        ["Set-Cookie"] = `__Secure-pastry-token=refresh; SameSite=Lax; Secure; Path=/; HostOnly=true; HttpOnly=true; Max-Age=0`,
    })
end

type UpdatePassword = {
    password: string,
    new_password: string,
}

function mod.update_password_request(p: { id: string }, h, c, b: http.Body): http.Response
    -- validate request
    if b:is_empty() then
        return helpers.api_return(false, general.error_msg(general.error("EmptyBody", nil)), nil)
    end

    local fail_reason = ""
    local ok, req: UpdatePassword = xpcall(function()
        return json.deserialize_validated(b:as_string(), {
            password = {
                options = { String = {
                    min_length = 6,
                } },
                required = true,
            },
            new_password = {
                options = { String = {
                    min_length = 6,
                } },
                required = true,
            },
        })
    end, function(e: string)
        fail_reason = tostring(e)
    end)

    if not ok then
        return helpers.api_return(false, general.error_msg(general.error("General", fail_reason:split("\n")[1])), nil)
    end

    -- ...
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    -- return
    local res = users.update_user_password(p.id, req.password, req.new_password, user)

    if res.is_ok then
        return helpers.api_return(true, "Success", nil)
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

type UpdateUsername = {
    username: string,
}

function mod.update_username_request(p: { id: string }, h, c, b: http.Body): http.Response
    -- validate request
    if b:is_empty() then
        return helpers.api_return(false, general.error_msg(general.error("EmptyBody", nil)), nil)
    end

    local fail_reason = ""
    local ok, req: UpdateUsername = xpcall(function()
        return json.deserialize_validated(b:as_string(), {
            username = {
                options = {
                    String = {
                        min_length = 2,
                        max_length = 32,
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

    -- ...
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    -- return
    local res = users.update_user_username(p.id, req.username, user)

    if res.is_ok then
        return helpers.api_return(true, "Success", nil)
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

type UpdateBanned = {
    banned: boolean,
}

function mod.update_banned_request(p: { id: string }, h, c, b: http.Body): http.Response
    -- validate request
    if b:is_empty() then
        return helpers.api_return(false, general.error_msg(general.error("EmptyBody", nil)), nil)
    end

    local req: UpdateBanned = json.deserialize(b:as_string())

    -- ...
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    -- return
    local res = users.update_user_banned(p.id, req.banned, user)

    if res.is_ok then
        return helpers.api_return(true, "Success", nil)
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

type UpdateBanReason = {
    reason: string,
}

function mod.update_ban_reason_request(p: { id: string }, h, c, b: http.Body): http.Response
    -- validate request
    if b:is_empty() then
        return helpers.api_return(false, general.error_msg(general.error("EmptyBody", nil)), nil)
    end

    local req: UpdateBanReason = json.deserialize_validated(b:as_string(), {
        reason = {
            options = { String = {
                max_length = 256,
                min_length = 0,
            } },
            required = true,
        },
    })

    -- ...
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    -- return
    local res = users.update_user_ban_reason(p.id, req.reason, user)

    if res.is_ok then
        return helpers.api_return(true, "Success", nil)
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

type UpdatePermissions = {
    permissions: { user.UserPermission },
}

function mod.update_permissions_request(p: { id: string }, h, c, b: http.Body): http.Response
    -- validate request
    if b:is_empty() then
        return helpers.api_return(false, general.error_msg(general.error("EmptyBody", nil)), nil)
    end

    local req: UpdatePermissions = json.deserialize(b:as_string())

    -- ...
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    -- return
    local res = users.update_user_permissions(p.id, array.dedup(req.permissions), user)

    if res.is_ok then
        return helpers.api_return(true, "Success", nil)
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

type UpdateSettings = {
    settings: user.UserSettings,
}

function mod.update_settings_request(p: { id: string }, h, c, b: http.Body): http.Response
    -- validate request
    if b:is_empty() then
        return helpers.api_return(false, general.error_msg(general.error("EmptyBody", nil)), nil)
    end

    local req: UpdateSettings = json.deserialize(b:as_string())

    -- ...
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    -- return
    local res = users.update_user_settings(p.id, req.settings, user)

    if res.is_ok then
        return helpers.api_return(true, "Success", nil)
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

type UpdateBadges = {
    badges: { user.UserBadge },
}

function mod.update_badges_request(p: { id: string }, h, c, b: http.Body): http.Response
    -- validate request
    if b:is_empty() then
        return helpers.api_return(false, general.error_msg(general.error("EmptyBody", nil)), nil)
    end

    local req: UpdateBadges = json.deserialize(b:as_string())

    -- ...
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    -- return
    local res = users.update_user_badges(p.id, array.dedup(req.badges), user)

    if res.is_ok then
        return helpers.api_return(true, "Success", nil)
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

type DeleteUser = {
    password: string,
}

function mod.delete_request(p: { id: string }, h, c, b: http.Body): http.Response
    -- validate request
    if b:is_empty() then
        return helpers.api_return(false, general.error_msg(general.error("EmptyBody", nil)), nil)
    end

    local req: DeleteUser = json.deserialize(b:as_string())

    -- ...
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    -- return
    local res = users.delete_user(p.id, user, req.password)

    if res.is_ok then
        return helpers.api_return(true, "Success", nil)
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

function mod.delete_notif_request(p: { id: string }, h, c): http.Response
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    -- return
    local res = notifs.delete_notification(p.id, user)

    if res.is_ok then
        return helpers.api_return(true, "Success", nil)
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

return mod
