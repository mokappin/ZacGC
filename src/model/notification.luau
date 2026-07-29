local tools = require("@webc/tools")

export type Notification = {
    id: string,
    created: number,
    owner: string,
    content: string,
    href: string,
}

local Notification = {}

function Notification.new(owner: string, content: string, href: string): Notification
    return {
        id = tools.id(),
        created = tools.unix_epoch_timestamp(),
        owner = owner,
        content = content,
        href = href,
    }
end

return Notification
