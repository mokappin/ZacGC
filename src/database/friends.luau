local Result = require("@collections/Result")
local array = require("@webc/array")
local ccfg = require("@webc/sql_common")
local psql = require("@webc/psql")

local friendships = require("../model/friends")
local general = require("../general")
local notification = require("../model/notification")
local notifs = require("./notifications")
local user = require("../model/user")
local users = require("./users")

local friends = {}

function friends.create_table(): ()
    psql.macros.execute(
        [[CREATE TABLE IF NOT EXISTS p_friendships (
            id TEXT NOT NULL PRIMARY KEY,
            created BIGINT NOT NULL,
            user1 TEXT NOT NULL REFERENCES p_users(id) ON DELETE CASCADE,
            user2 TEXT NOT NULL REFERENCES p_users(id) ON DELETE CASCADE,
            status INT NOT NULL,
            UNIQUE (user1, user2),
            UNIQUE (user2, user1)
        )]],
        {}
    )
end

local friendship_read_fields: ccfg.SqlReadColsAs = {
    { key = "id", ty = "String" },
    { key = "created", ty = "i64" },
    { key = "user1", ty = "String" },
    { key = "user2", ty = "String" },
    { key = "status", ty = "i32" },
}

function read_row_as_friendship(row: { [string]: any }): Result.Result<friendships.Friendship, general.Error<any>>
    if row == nil then
        return Result.Err(general.error("General", "no such friendship"))
    end

    return Result.Ok({
        id = row.id,
        created = row.created,
        user1 = row.user1,
        user2 = row.user2,
        status = row.status,
    })
end

function friends.get_friendship_by_users(
    user1: string,
    user2: string
): Result.Result<friendships.Friendship, general.Error<any>>
    -- attempt to pull
    local err = ""
    local ok, res = xpcall(function()
        return psql.macros.query_row(
            "SELECT * FROM p_friendships WHERE (user1 = $1 AND user2 = $2) OR (user1 = $2 AND user2 = $1) LIMIT 1",
            { { v = user1, ty = "String" }, { v = user2, ty = "String" } },
            friendship_read_fields
        )
    end, function(e)
        err = e
    end)

    if not ok then
        return Result.Err(general.error("General", "no such friendship"))
    end

    local friendship = read_row_as_friendship(res)

    -- return
    return friendship
end

function friends.get_friendships_by_user_status(
    user: string,
    status: friendships.StatusString,
    batch: number,
    page: number
): Result.Result<{ friendships.Friendship }, general.Error<any>>
    local friendships_: { friendships.Friendship } = {}

    for _, f in
        pairs(
            psql.macros.query_rows(
                "SELECT * FROM p_friendships WHERE (user1 = $1 OR user2 = $1) AND status = $2 ORDER BY created DESC LIMIT $3 OFFSET $4",
                {
                    { v = user, ty = "String" },
                    { v = friendships.status(status), ty = "i32" },
                    { v = batch, ty = "i64" },
                    { v = batch * page, ty = "i64" },
                },
                friendship_read_fields
            )
        )
    do
        array.push(friendships_, (read_row_as_friendship(f) :: Result.Ok<friendships.Friendship>):unwrap())
    end

    return Result.Ok(friendships_)
end

function friends.create_friendship(
    data: friendships.Friendship
): Result.Result<friendships.Friendship, general.Error<any>>
    -- make sure users exist
    local sender = users.get_user_by_id(data.user1)

    if sender.is_err then
        return Result.Err(general.error("UserNotFound", nil))
    end

    local sender = sender:unwrap()

    if users.get_user_by_id(data.user2).is_err then
        return Result.Err(general.error("UserNotFound", nil))
    end

    -- ...
    local ok, _: string? = pcall(function()
        psql.macros.execute("INSERT INTO p_friendships VALUES ($1, $2, $3, $4, $5)", {
            { v = data.id, ty = "String" },
            { v = data.created, ty = "i64" },
            { v = data.user1, ty = "String" },
            { v = data.user2, ty = "String" },
            { v = data.status, ty = "i32" },
        })
    end)

    if not ok then
        return Result.Err(general.error("DatabaseError", nil))
    end

    -- send notification
    -- this should use a redirect route with the sender's id in the future, but whatever
    notifs.create_notif(
        notification.new(
            data.user2,
            `You've received a new friend request from @{sender.username}!`,
            `/@{sender.username}`
        )
    )

    -- ...
    return Result.Ok(data)
end

function friends.update_friendship_status(
    other_user: string,
    as_user: user.User,
    status: number
): Result.Result<friendships.Friendship, general.Error<any>>
    local y = friends.get_friendship_by_users(other_user, as_user.id)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    local y = y:unwrap()

    if y.user2 ~= as_user.id then
        -- user2 represents the receiving user, which is the only one who can accept the request
        return Result.Err(general.error("NotAllowed", nil))
    end

    local ok, _: string? = pcall(function()
        psql.macros.execute("UPDATE p_friendships SET status = $1 WHERE id = $2", {
            { v = status, ty = "i32" },
            { v = y.id, ty = "String" },
        })
    end)

    if not ok then
        return Result.Err(general.error("DatabaseError", nil))
    end

    -- return
    return Result.Ok(y)
end

function friends.delete_friendship(other_user: string, as_user: user.User): Result.Result<nil, general.Error<any>>
    local y = friends.get_friendship_by_users(other_user, as_user.id)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    local y = y:unwrap()

    local ok, _: string? = pcall(function()
        psql.macros.execute("DELETE FROM p_friendships WHERE id = $1", {
            { v = y.id, ty = "String" },
        })
    end)

    if not ok then
        return Result.Err(general.error("DatabaseError", nil))
    end

    -- return
    return Result.Ok(nil)
end

return friends
