local tools = require("@webc/tools")

export type UserSessionValue = { ip: string, t: string, ts: number }
export type UserPermission = "ManagePastes" | "ManageUsers" | "Administrator" | "AccessModPanel"

export type UserSettings = {
    bio: string,
    css: string,
    avatar_url: string,
}

export type UserBadge = "BetaTester" | "Contributor" | "Staff" | "Supporter"

export type User = {
    id: string,
    created: number,
    username: string,
    password: string,
    salt: string,
    sessions: { UserSessionValue },
    permissions: { UserPermission },
    banned: boolean,
    ban_reason: string,
    settings: UserSettings,
    notification_count: number,
    badges: { UserBadge },
    pastes: number,
}

local User = {}

function User.new(username: string, password: string): User
    local salt = tools.salt()
    local hashed = tools.sha256(password .. salt)

    return {
        id = tools.id(),
        created = tools.unix_epoch_timestamp(),
        username = username,
        password = hashed,
        salt = salt,
        sessions = {},
        username_changed = 0,
        permissions = {},
        banned = false,
        ban_reason = "",
        settings = {
            bio = "",
            css = "",
            avatar_url = "",
        },
        notification_count = 0,
        badges = {},
        pastes = 0,
    }
end

return User
