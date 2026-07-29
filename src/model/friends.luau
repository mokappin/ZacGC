local features = require("@webc/features")
local tools = require("@webc/tools")

export type StatusString = "Friends" | "Requested"

export type Friendship = {
    id: string,
    created: number,
    user1: string,
    user2: string,
    status: number,
}

local Friendship = {}

function Friendship.new(user1: string, user2: string, status: number): Friendship
    return {
        id = tools.id(),
        created = tools.unix_epoch_timestamp(),
        user1 = user1,
        user2 = user2,
        status = status,
    }
end

function Friendship.status(s: StatusString): number
    return features.match(s, {
        ["Friends"] = 0,
        ["Requested"] = 1,
        _ = function()
            features.throw(`Unknown status: {s}`)
        end,
    })
end

return Friendship
