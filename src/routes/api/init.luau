local friends = require("@self/friends")
local http = require("@webc/http")
local ip_bans = require("@self/ip_bans")
local pastes = require("@self/pastes")
local users = require("@self/users")

local rt = {
    -- users
    ["/api/v1/users"] = { m = "POST", h = users.create_request },
    ["/api/v1/users/login"] = { m = "POST", h = users.login_request },
    ["/api/v1/users/logout"] = { m = "POST", h = users.logout_request },
    ["/api/v1/users/{id}"] = { m = "DELETE", h = users.delete_request },
    ["/api/v1/users/{id}/password"] = { m = "POST", h = users.update_password_request },
    ["/api/v1/users/{id}/username"] = { m = "POST", h = users.update_username_request },
    ["/api/v1/users/{id}/banned"] = { m = "POST", h = users.update_banned_request },
    ["/api/v1/users/{id}/ban_reason"] = { m = "POST", h = users.update_ban_reason_request },
    ["/api/v1/users/{id}/permissions"] = { m = "POST", h = users.update_permissions_request },
    ["/api/v1/users/{id}/settings"] = { m = "POST", h = users.update_settings_request },
    ["/api/v1/users/{id}/badges"] = { m = "POST", h = users.update_badges_request },
    -- notifications
    ["/api/v1/notifications/{id}"] = { m = "DELETE", h = users.delete_notif_request },
    -- pastes
    ["/api/v1/pastes"] = { m = "POST", h = pastes.create_request },
    ["/api/v1/pastes/{id}"] = { m = "POST", h = pastes.update_paste_request },
    ["=/api/v1/pastes/{id}"] = { m = "DELETE", h = pastes.delete_request },
    ["/api/v1/pastes/{id}/slug"] = { m = "POST", h = pastes.update_slug_request },
    ["/api/v1/pastes/{id}/settings"] = { m = "POST", h = pastes.update_settings_request },
    ["/api/v1/pastes/{id}/transfer"] = { m = "POST", h = pastes.update_owner_request },
    ["/api/v1/pastes/{id}/is_locked"] = { m = "POST", h = pastes.update_is_locked_request },
    ["/api/v1/preview"] = { m = "POST", h = pastes.render_preview_request },
    -- friendships
    ["/api/v1/friendships/{other_user}"] = { m = "POST", h = friends.create_request },
    ["=/api/v1/friendships/{other_user}"] = { m = "DELETE", h = friends.delete_request },
    ["/api/v1/friendships/{other_user}/approve"] = { m = "POST", h = friends.approve_request },
    -- ip bans
    ["/api/v1/ip_bans"] = { m = "POST", h = ip_bans.create_request },
    ["/api/v1/ip_bans/{ip}"] = { m = "DELETE", h = ip_bans.delete_request },
}

return function(proc: http.SplitProcess)
    for p, x in pairs(rt) do
        -- skip padding (=)
        -- routes are padded because they *technically* would collide since we're
        -- doing routes in a table format
        local np = ""

        for _, a in pairs(p:split("=")) do
            np = np .. a
        end

        -- ...
        proc.route(x.m, np, x.h)
    end
end
