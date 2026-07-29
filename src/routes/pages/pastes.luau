local array = require("@webc/array")
local http = require("@webc/http")
local option = require("@collections/Option")
local tera = require("@webc/tera")
local tools = require("@webc/tools")

local api = require("../api/pastes")
local general = require("../../general")
local helpers = require("./helpers")
local pastes = require("../../database/pastes")
local user = require("../../model/user")
local users = require("../../database/users")

local mod = {}

function mod.my_pastes_request(_, _, c, _, q: helpers.PaginatedQuery): http.Response
    if not q.page then
        q.page = 0
    end

    local user = users.get_user_from_cookie(c)
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token_pages_required.macro.luau>

    -- fetch pastes
    local pastes = pastes.get_pastes_by_owner(user.id, 8, q.page)

    if pastes.is_err then
        return helpers.return_error(pastes:unwrap_err(), helpers.default_context(option.Some(user)))
    end

    local pastes = pastes:unwrap()

    -- ...
    local ctx = helpers.default_context(option.Some(user))

    ctx.pastes = pastes
    ctx.page = tonumber(q.page)

    return helpers.html(tera.render("my_pastes.html", ctx))
end

function mod.view_paste_request(p: { ["slug"]: string }, _, c, _, _): http.Response
    local user = helpers.result_to_option(users.get_user_from_cookie(c))

    -- fetch paste
    local paste = pastes.get_paste_by_slug(p.slug)

    if paste.is_err then
        return helpers.return_error(paste:unwrap_err(), helpers.default_context(user))
    end

    local paste = paste:unwrap()

    if
        paste.is_locked
        and (
            user.is_none
            or not array.contains((user:unwrap() :: user.User).permissions, "ManagePastes" :: user.UserPermission)
        )
    then
        return helpers.return_error(general.error("NotAllowed", nil), helpers.default_context(user))
    end

    -- incr views
    if not c["Viewed"] then
        local r = pastes.incr_paste_views(paste.id)

        if r.is_err then
            return helpers.return_error(r:unwrap_err(), helpers.default_context(user))
        end
    end

    -- fetch owner
    local owner = users.get_user_by_id(paste.owner)

    if owner.is_err then
        return helpers.return_error(owner:unwrap_err(), helpers.default_context(user))
    end

    local owner = owner:unwrap()

    -- ...
    local ctx = helpers.default_context(user)

    ctx.paste = paste
    ctx.owner = owner
    ctx.paste_content = `{api.sanitize(paste.html)}<style>{paste.css}</style>`

    return helpers.html_headers(tera.render("paste.html", ctx), {
        ["Set-Cookie"] = `Viewed=true; Path=/{paste.slug}; Max-Age=86400`,
    })
end

function mod.edit_paste_request(p: { ["slug"]: string }, _, c, _, _): http.Response
    local user = users.get_user_from_cookie(c)
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token_pages_required.macro.luau>

    -- fetch paste
    local paste = pastes.get_paste_by_slug(p.slug)

    if paste.is_err then
        return helpers.return_error(paste:unwrap_err(), helpers.default_context(option.Some(user)))
    end

    local paste = paste:unwrap()

    if paste.is_locked and not array.contains(user.permissions, "ManagePastes" :: user.UserPermission) then
        return helpers.return_error(general.error("NotAllowed", nil), helpers.default_context(option.Some(user)))
    end

    -- ...
    local ctx = helpers.default_context(option.Some(user))

    ctx.paste = paste
    ctx.paste_html_clean = helpers.remove_script_tags(paste.html)
    ctx.paste_css_clean = helpers.remove_script_tags(paste.css)

    return helpers.html(tera.render("edit_paste.html", ctx))
end

function mod.edit_paste_settings_request(p: { ["slug"]: string }, _, c, _, _): http.Response
    local user = users.get_user_from_cookie(c)
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token_pages_required.macro.luau>

    -- fetch paste
    local paste = pastes.get_paste_by_slug(p.slug)

    if paste.is_err then
        return helpers.return_error(paste:unwrap_err(), helpers.default_context(option.Some(user)))
    end

    local paste = paste:unwrap()

    if paste.is_locked and not array.contains(user.permissions, "ManagePastes" :: user.UserPermission) then
        return helpers.return_error(general.error("NotAllowed", nil), helpers.default_context(option.Some(user)))
    end

    -- check permissions
    if user.id ~= paste.owner and not array.contains(user.permissions, "ManagePastes" :: user.UserPermission) then
        return helpers.return_error(general.error("NotAllowed", nil), helpers.default_context(option.Some(user)))
    end

    -- ...
    local ctx = helpers.default_context(option.Some(user))
    ctx.paste = paste

    return helpers.html(tera.render("edit_paste_settings.html", ctx))
end

local MINIMUM_CLAIM_TIME = 2_419_200_000 * 3 -- 3 months

function mod.file_claim_request(p: { ["slug"]: string }, _, c, _, _): http.Response
    local user = users.get_user_from_cookie(c)
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token_pages_required.macro.luau>

    -- fetch paste
    local paste = pastes.get_paste_by_slug(p.slug)

    if paste.is_err then
        return helpers.return_error(paste:unwrap_err(), helpers.default_context(option.Some(user)))
    end

    local paste = paste:unwrap()
    local now = tools.unix_epoch_timestamp()
    local is_claimable = (now - paste.edited) >= MINIMUM_CLAIM_TIME

    -- ...
    local ctx = helpers.default_context(option.Some(user))

    ctx.paste = paste
    ctx.claimable = is_claimable

    return helpers.html(tera.render("paste_claim.html", ctx))
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
    if not array.contains(user.permissions, "ManagePastes" :: user.UserPermission) then
        return helpers.return_error(general.error("NotAllowed", nil), helpers.default_context(option.Some(user)))
    end

    -- fetch pastes
    local pastes = pastes.get_pastes_by_query(q.query, 12, q.page)

    if pastes.is_err then
        return helpers.return_error(pastes:unwrap_err(), helpers.default_context(option.Some(user)))
    end

    local pastes = pastes:unwrap()
    local pastes_ = {}

    for _, paste in pastes do
        local owner = users.get_user_by_id(paste.owner)

        if owner.is_err then
            return helpers.return_error(owner:unwrap_err(), helpers.default_context(option.Some(user)))
        end

        local owner = owner:unwrap()

        array.push(pastes_, { paste = paste, owner = owner })
    end

    -- ...
    local ctx = helpers.default_context(option.Some(user))

    ctx.pastes = pastes_
    ctx.query = q.query
    ctx.page = tonumber(q.page)

    return helpers.html(tera.render("search_pastes.html", ctx))
end

return mod
