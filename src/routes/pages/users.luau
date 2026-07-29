local array = require("@webc/array")
local http = require("@webc/http")
local option = require("@collections/Option")
local tera = require("@webc/tera")

local api = require("../api/pastes")
local friendships = require("../../database/friends")
local general = require("../../general")
local helpers = require("./helpers")
local ip_bans = require("../../database/ip_bans")
local notifs = require("../../database/notifications")
local pastes = require("../../database/pastes")
local user = require("../../model/user")
local users = require("../../database/users")

local mod = {}

function mod.profile_request(p: { ["username"]: string }, _, c, _, q: helpers.PaginatedQuery): http.Response
    if not q.page then
        q.page = 0
    end

    local user = helpers.result_to_option(users.get_user_from_cookie(c))

    -- fetch user
    local profile = users.get_user_by_username(p.username)

    if profile.is_err then
        return helpers.return_error(general.error("UserNotFound", nil), helpers.default_context(user))
    end

    local profile = profile:unwrap()

    -- fetch friends
    local friends = friendships.get_friendships_by_user_status(profile.id, "Friends", 12, q.page)

    if friends.is_err then
        return helpers.return_error(general.error("UserNotFound", nil), helpers.default_context(user))
    end

    local friends = friends:unwrap()
    local friends_ = {}

    for _, f in pairs(friends) do
        local f_user = users.get_user_by_id(if f.user2 == profile.id then f.user1 else f.user2)

        if f_user.is_err then
            continue
        end

        local f_user = f_user:unwrap()
        array.push(friends_, f_user)
    end

    -- get existing friendship
    local existing_friendship = nil

    if user.is_some then
        local friendship_ = friendships.get_friendship_by_users(user:unwrap().id, profile.id)

        if friendship_.is_ok then
            existing_friendship = friendship_:unwrap()
        end
    end

    -- ...
    local ctx = helpers.default_context(user)

    ctx.existing_friendship = existing_friendship
    ctx.profile = profile
    ctx.friends = friends_
    ctx.page = tonumber(q.page)

    if profile.settings.bio then
        ctx.bio_html =
            `{api.sanitize(profile.settings.bio)}<style>{helpers.remove_script_tags(profile.settings.css)}</style>`
    end

    return helpers.html(tera.render("profile.html", ctx))
end

function mod.settings_request(_, _, c, _): http.Response
    local user = users.get_user_from_cookie(c)
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token_pages_required.macro.luau>
    return helpers.html(tera.render("settings.html", helpers.default_context(option.Some(user))))
end

function mod.my_notifs_request(_, _, c, _, q: helpers.PaginatedQuery): http.Response
    if not q.page then
        q.page = 0
    end

    local user = users.get_user_from_cookie(c)
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token_pages_required.macro.luau>

    -- fetch notifs
    local notifs = notifs.get_notifs_by_owner(user.id, 12, q.page)

    if notifs.is_err then
        return helpers.return_error(notifs:unwrap_err(), helpers.default_context(option.Some(user)))
    end

    local notifs = notifs:unwrap()

    -- ...
    local ctx = helpers.default_context(option.Some(user))

    ctx.notifs = notifs
    ctx.page = tonumber(q.page)

    return helpers.html(tera.render("my_notifs.html", ctx))
end

function mod.mod_manage_user_request(p: { ["username"]: string }, _, c, _, q: helpers.PaginatedQuery): http.Response
    if not q.page then
        q.page = 0
    end

    local user = users.get_user_from_cookie(c)
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token_pages_required.macro.luau>

    if not array.contains(user.permissions, "ManageUsers" :: user.UserPermission) then
        return helpers.return_error(general.error("NotAllowed", nil), helpers.default_context(option.Some(user)))
    end

    -- fetch profile
    local profile = users.get_user_by_username(p.username)

    if profile.is_err then
        return helpers.return_error(profile:unwrap_err(), helpers.default_context(option.Some(user)))
    end

    local profile = profile:unwrap()

    -- fetch pastes
    local pastes = pastes.get_pastes_by_owner(profile.id, 12, q.page)

    if pastes.is_err then
        return helpers.return_error(pastes:unwrap_err(), helpers.default_context(option.Some(user)))
    end

    local pastes = pastes:unwrap()

    -- ...
    local ctx = helpers.default_context(option.Some(user))

    ctx.profile = profile
    ctx.pastes = pastes
    ctx.page = tonumber(q.page)

    return helpers.html(tera.render("user_admin.html", ctx))
end

function mod.mod_manage_ip_bans_request(p, _, c, _, q: helpers.PaginatedQuery): http.Response
    if not q.page then
        q.page = 0
    end

    local user = users.get_user_from_cookie(c)
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token_pages_required.macro.luau>

    if not array.contains(user.permissions, "ManageUsers" :: user.UserPermission) then
        return helpers.return_error(general.error("NotAllowed", nil), helpers.default_context(option.Some(user)))
    end

    -- fetch bans
    local ip_bans = ip_bans.get_ip_bans(12, q.page)

    if ip_bans.is_err then
        return helpers.return_error(ip_bans:unwrap_err(), helpers.default_context(option.Some(user)))
    end

    local ip_bans = ip_bans:unwrap()

    -- ...
    local ctx = helpers.default_context(option.Some(user))

    ctx.ip_bans = ip_bans
    ctx.page = tonumber(q.page)

    return helpers.html(tera.render("ip_bans.html", ctx))
end

function mod.search_request(_, _, c, _, q: helpers.SearchedQuery): http.Response
    if not q.page then
        q.page = 0
    end

    if not q.query then
        q.query = ""
    end

    local user = users.get_user_from_cookie(c)
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token_pages_required.macro.luau>

    -- check permissions
    if not array.contains(user.permissions, "ManageUsers" :: user.UserPermission) then
        return helpers.return_error(general.error("NotAllowed", nil), helpers.default_context(option.Some(user)))
    end

    -- fetch users
    local users = users.get_users_by_query(q.query, 12, q.page)

    if users.is_err then
        return helpers.return_error(users:unwrap_err(), helpers.default_context(option.Some(user)))
    end

    local users = users:unwrap()

    -- ...
    local ctx = helpers.default_context(option.Some(user))

    ctx.query = q.query
    ctx.users = users
    ctx.page = tonumber(q.page)

    return helpers.html(tera.render("search_users.html", ctx))
end

return mod
