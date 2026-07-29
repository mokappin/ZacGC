local tools = require("@webc/tools")

export type IpBan = {
    id: string,
    created: number,
    owner: string,
    ip: string,
    reason: string,
}

local IpBan = {}

function IpBan.new(owner: string, ip: string, reason: string): IpBan
    return {
        id = tools.id(),
        created = tools.unix_epoch_timestamp(),
        owner = owner,
        ip = ip,
        reason = reason,
    }
end

return IpBan
