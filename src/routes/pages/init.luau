local http = require("@webc/http")
local misc = require("@self/misc")
local pastes = require("@self/pastes")
local users = require("@self/users")

local rt = {
    ["/"] = { m = "GET", h = misc.index_request },
    -- this user
    ["/register"] = { m = "GET", h = misc.register_request },
    ["/login"] = { m = "GET", h = misc.login_request },
    ["/user/settings"] = { m = "GET", h = users.settings_request },
    ["/user/pastes"] = { m = "GET", h = pastes.my_pastes_request },
    ["/user/notifs"] = { m = "GET", h = users.my_notifs_request },
    ["/user/ip_bans"] = { m = "GET", h = users.mod_manage_ip_bans_request },
    ["/user/search"] = { m = "GET", h = users.search_request },
    -- profile
    ["/@{username}"] = { m = "GET", h = users.profile_request },
    ["/@{username}/manage"] = { m = "GET", h = users.mod_manage_user_request },
    -- pastes
    ["/{slug}"] = { m = "GET", h = pastes.view_paste_request },
    ["/claim/{slug}"] = { m = "GET", h = pastes.file_claim_request },
    ["/edit/{slug}"] = { m = "GET", h = pastes.edit_paste_request },
    ["/edit/{slug}/settings"] = { m = "GET", h = pastes.edit_paste_settings_request },
    ["/pastes/search"] = { m = "GET", h = pastes.search_request },
}

return function(proc: http.SplitProcess)
    for p, x in pairs(rt) do
        proc.route(x.m, p, x.h)
    end
end
