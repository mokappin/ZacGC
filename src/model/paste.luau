local array = require("@webc/array")
local sc = require("@webc/serde_common")
local tools = require("@webc/tools")

local user = require("./user")

export type PasteSettings = {
    --- This pastes title in the URL bar.
    ---
    --- Default is the paste's slug.
    title: string,
    --- The URL of this paste's favicon image.
    favicon: string,
    --- The URL of the social color (opengraph) image for this paste.
    embed_color: string,
    --- The URL of the social embed (opengraph) image for this paste.
    embed_image: string,
    --- The ID of each user with write permissions (not delete) on this paste.
    collaborators: { string },
}

export type Paste = {
    id: string,
    created: number,
    edited: number,
    owner: string,
    slug: string,
    html: string,
    css: string,
    settings: PasteSettings,
    views: number,
    is_locked: boolean,
}

local Paste = {}

Paste.PASTE_SETTINGS_VALIDATION = {
    title = {
        options = { String = {
            max_length = 128,
            min_length = 0,
        } },
        required = true,
    },
    favicon = {
        options = { String = {
            max_length = 256,
            min_length = 0,
        } },
        required = true,
    },
    embed_color = {
        options = { String = {
            max_length = 64,
            min_length = 0,
        } },
        required = true,
    },
    embed_image = {
        options = { String = {
            max_length = 256,
            min_length = 0,
        } },
        required = true,
    },
    -- no validation for collaborators; we have to do that separately
} :: sc.ValidatedDeserializeOptions

function Paste.new(owner: string, slug: string, html: string, css: string): Paste
    local now = tools.unix_epoch_timestamp()

    return {
        id = tools.id(),
        created = now,
        edited = now,
        owner = owner,
        slug = slug,
        html = html,
        css = css,
        settings = {
            title = "",
            favicon = "",
            embed_color = "",
            embed_image = "",
            collaborators = {},
        },
        views = 0,
        is_locked = false,
    }
end

--- check if the user can manage the paste as a collaborator (change content)
function Paste.can_edit(self: Paste, me: user.User): boolean
    return (self.owner == me.id)
        or array.contains(self.settings.collaborators, me.id)
        or array.contains(me.permissions, "ManagePastes" :: user.UserPermission)
end

--- check if the user can manage the paste as a manager (delete/change slug)
function Paste.can_manage(self: Paste, me: user.User): boolean
    return (self.owner == me.id) or array.contains(me.permissions, "ManagePastes" :: user.UserPermission)
end

return Paste
