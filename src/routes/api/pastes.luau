local array = require("@webc/array")
local http = require("@webc/http")
local json = require("@webc/json")
local option = require("@collections/Option")
local tera = require("@webc/tera")

local _ip_bans = require("../../database/ip_bans")
local general = require("../../general")
local helpers = require("./helpers")
local paste = require("../../model/paste")
local pastes = require("../../database/pastes")
local user = require("../../model/user")
local users = require("../../database/users")

local mod = {}

local PASTE_SLUG_VALIDATION = {
    options = { String = {
        min_length = 0,
        max_length = 32,
    } },
    required = true,
}

local PASTE_HTML_VALIDATION = {
    options = { String = {
        min_length = 1,
        max_length = 8192,
    } },
    required = true,
}

local PASTE_CSS_VALIDATION = {
    options = { String = {
        min_length = 0,
        max_length = 4096,
    } },
    required = true,
}

type CreatePaste = {
    slug: string,
    html: string,
    css: string,
}

local PASTES_PERIOD = 1000 * 60 * 60 * 24 -- 1 day
local MAXIMUM_PASTES_IN_PERIOD = 8 -- 8 pastes per period
local MAXIMUM_TOTAL_PASTES = 256 -- 256 pastes per user total

function check_user_limits(user: user.User): option.Option<http.Response>
    -- check total
    if user.pastes >= MAXIMUM_TOTAL_PASTES then
        return option.Some(
            helpers.api_return(
                false,
                general.error_msg(
                    general.error("General", `User can only own a maximum of {MAXIMUM_TOTAL_PASTES} pastes`)
                ),
                nil
            )
        )
    end

    -- check period
    local pastes = pastes.get_paste_count_by_owner_period(user.id, PASTES_PERIOD)
    local pastes_in_period = if pastes.is_ok then pastes:unwrap() else 0

    if pastes_in_period >= MAXIMUM_PASTES_IN_PERIOD then
        return option.Some(
            helpers.api_return(
                false,
                general.error_msg(general.error("General", "User has created too many pastes too recently")),
                nil
            )
        )
    end

    -- all good
    return option.None()
end

function mod.create_request(_, h, c, b: http.Body): http.Response
    -- validate request
    if b:is_empty() then
        return helpers.api_return(false, general.error_msg(general.error("EmptyBody", nil)), nil)
    end

    local fail_reason = ""
    local ok, req: CreatePaste = xpcall(function()
        return json.deserialize_validated(b:as_string(), {
            slug = PASTE_SLUG_VALIDATION,
            html = PASTE_HTML_VALIDATION,
            css = PASTE_CSS_VALIDATION,
        })
    end, function(e: string)
        fail_reason = tostring(e)
    end)

    if not ok then
        return helpers.api_return(false, general.error_msg(general.error("General", fail_reason:split("\n")[1])), nil)
    end

    -- !<macros/check_for_ip_ban.macro.luau>

    -- ...
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    if user.banned then
        return helpers.api_return(false, general.error_msg(general.error("NotAllowed", nil)), nil)
    end

    -- check limits
    local x = check_user_limits(user)

    if x.is_some then
        return x:unwrap()
    end

    -- create paste
    local res = pastes.create_paste(paste.new(user.id, req.slug:lower(), req.html, req.css))

    if res.is_ok then
        return helpers.api_return(true, "Success", res:unwrap())
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

type UpdatePaste = {
    html: string,
    css: string,
}

function mod.update_paste_request(p: { id: string }, h, c, b: http.Body): http.Response
    -- validate request
    if b:is_empty() then
        return helpers.api_return(false, general.error_msg(general.error("EmptyBody", nil)), nil)
    end

    local fail_reason = ""
    local ok, req: UpdatePaste = xpcall(function()
        return json.deserialize_validated(b:as_string(), {
            html = PASTE_HTML_VALIDATION,
            css = PASTE_CSS_VALIDATION,
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

    if user.banned then
        return helpers.api_return(false, general.error_msg(general.error("NotAllowed", nil)), nil)
    end

    -- return
    local res = pastes.update_paste_content(p.id, req.html, req.css, user)

    if res.is_ok then
        return helpers.api_return(true, "Success", nil)
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

type UpdateSlug = {
    slug: string,
}

function mod.update_slug_request(p: { id: string }, h, c, b: http.Body): http.Response
    -- validate request
    if b:is_empty() then
        return helpers.api_return(false, general.error_msg(general.error("EmptyBody", nil)), nil)
    end

    local fail_reason = ""
    local ok, req: UpdateSlug = xpcall(function()
        return json.deserialize_validated(b:as_string(), {
            slug = PASTE_SLUG_VALIDATION,
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

    if user.banned then
        return helpers.api_return(false, general.error_msg(general.error("NotAllowed", nil)), nil)
    end

    -- return
    local res = pastes.update_paste_slug(p.id, req.slug:lower(), user)

    if res.is_ok then
        return helpers.api_return(true, "Success", nil)
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

function mod.update_settings_request(p: { id: string }, h, c, b: http.Body): http.Response
    -- validate request
    if b:is_empty() then
        return helpers.api_return(false, general.error_msg(general.error("EmptyBody", nil)), nil)
    end

    local fail_reason = ""
    local ok, req: paste.PasteSettings = xpcall(function()
        return json.deserialize_validated(b:as_string(), paste.PASTE_SETTINGS_VALIDATION)
    end, function(e: string)
        fail_reason = tostring(e)
    end)

    if not ok then
        return helpers.api_return(false, general.error_msg(general.error("General", fail_reason:split("\n")[1])), nil)
    end

    for _, u in pairs(req.collaborators) do
        -- u is defined as an id, not a username!
        local ua = users.get_user_by_id(u)

        if ua.is_err then
            return helpers.api_return(false, general.error_msg(general.error("UserNotFound", u)), nil)
        end
    end

    -- ...
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    if user.banned then
        return helpers.api_return(false, general.error_msg(general.error("NotAllowed", nil)), nil)
    end

    -- return
    local res = pastes.update_paste_settings(p.id, req, user)

    if res.is_ok then
        return helpers.api_return(true, "Success", nil)
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

function mod.delete_request(p: { id: string }, _, c): http.Response
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    -- return
    local res = pastes.delete_paste(p.id, user)

    if res.is_ok then
        return helpers.api_return(true, "Success", nil)
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

type UpdateIsLocked = {
    is_locked: boolean,
}

function mod.update_is_locked_request(p: { id: string }, h, c, b: http.Body): http.Response
    -- validate request
    if b:is_empty() then
        return helpers.api_return(false, general.error_msg(general.error("EmptyBody", nil)), nil)
    end

    local fail_reason = ""
    local ok, req: UpdateIsLocked = xpcall(function()
        return json.deserialize(b:as_string())
    end, function(e: string)
        fail_reason = tostring(e)
    end)

    if not ok then
        return helpers.api_return(false, general.error_msg(general.error("General", fail_reason:split("\n")[1])), nil)
    end

    -- ...
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    if user.banned then
        return helpers.api_return(false, general.error_msg(general.error("NotAllowed", nil)), nil)
    end

    -- return
    local res = pastes.update_paste_is_locked(p.id, if req.is_locked == nil then false else req.is_locked, user)

    if res.is_ok then
        return helpers.api_return(true, "Success", nil)
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

function mod.sanitize(haystack: string): string
    return http.sanitize_with_simple(
        haystack,
        array.concat(http.sanitize_get_default_tags(), { "style" }),
        { "class", "id", "style", "title", "alt", "src", "href" }
    )
end

type RenderPreview = {
    html: string,
    css: string,
}

function mod.render_preview_request(
    _,
    _,
    _,
    b: http.Body,
    q: { ["theme"]: "light" | "dark", ["stylesheet"]: string }
): http.Response
    local req = json.deserialize(b:as_string())
    return helpers.api_return(
        true,
        "Success",
        tera.render("preview.html", {
            ["theme"] = q.theme or "light",
            ["stylesheet"] = q.stylesheet,
            paste_content = if #req.html == 0
                then "Live preview will show here as you type!"
                else `{mod.sanitize(req.html)}<style>{req.css}</style>`,
        })
    )
end

type TransferOwnership = {
    username: string,
}

function mod.update_owner_request(p: { id: string }, h, c, b: http.Body): http.Response
    -- validate request
    if b:is_empty() then
        return helpers.api_return(false, general.error_msg(general.error("EmptyBody", nil)), nil)
    end

    local req: TransferOwnership = json.deserialize(b:as_string())

    -- ...
    local user: user.User = nil :: any
    -- !<macros/get_user_from_token.macro.luau>

    if user.banned then
        return helpers.api_return(false, general.error_msg(general.error("NotAllowed", nil)), nil)
    end

    -- return
    local res = pastes.update_paste_owner(p.id, req.username, user)

    if res.is_ok then
        return helpers.api_return(true, "Success", nil)
    else
        return helpers.api_return(false, general.error_msg(res:unwrap_err()), nil)
    end
end

return mod
