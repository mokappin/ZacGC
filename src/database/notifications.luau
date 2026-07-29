local Result = require("@collections/Result")
local array = require("@webc/array")
local ccfg = require("@webc/sql_common")
local json = require("@webc/json")
local psql = require("@webc/psql")
local redis = require("@webc/redis")

local general = require("../general")
local notification = require("../model/notification")
local user = require("../model/user")
local users = require("./users")

local notifs = {}

function notifs.create_table(): ()
    psql.macros.execute(
        [[CREATE TABLE IF NOT EXISTS p_notifications (
            id TEXT NOT NULL PRIMARY KEY,
            created BIGINT NOT NULL,
            owner TEXT NOT NULL REFERENCES p_users(id) ON DELETE CASCADE,
            content TEXT NOT NULL,
            href TEXT NOT NULL
        )]],
        {}
    )
end

local notif_read_fields: ccfg.SqlReadColsAs = {
    { key = "id", ty = "String" },
    { key = "created", ty = "i64" },
    { key = "owner", ty = "String" },
    { key = "content", ty = "String" },
    { key = "href", ty = "String" },
}

function read_row_as_notif(row: { [string]: any }): Result.Result<notification.Notification, general.Error<any>>
    if row == nil then
        return Result.Err(general.error("General", "no such friendship"))
    end

    return Result.Ok({
        id = row.id,
        created = row.created,
        owner = row.owner,
        content = row.content,
        href = row.href,
    })
end

function cache_clear_notif(notif: notification.Notification): ()
    redis.remove(`psng.notif:{notif.id}`)
end

function notifs.get_notif_by_id(id: string): Result.Result<notification.Notification, general.Error<any>>
    local redis_paste = redis.get(`psng.paste:{id}`)
    if redis_paste then
        return Result.Ok(json.deserialize(redis_paste))
    end

    -- attempt to pull
    local err = ""
    local ok, res = xpcall(function()
        return psql.macros.query_row(
            "SELECT * FROM p_notifications WHERE id = $1 LIMIT 1",
            { { v = id, ty = "String" } },
            notif_read_fields
        )
    end, function(e)
        err = e
    end)

    if not ok then
        return Result.Err(general.error("General", err))
    end

    local notif = read_row_as_notif(res)

    -- return
    if notif.is_ok then
        redis.set(`psng.notif:{id}`, json.serialize(notif:unwrap()))
    end

    return notif
end

function notifs.get_notifs_by_owner(
    owner: string,
    batch: number,
    page: number
): Result.Result<{ notification.Notification }, general.Error<any>>
    local notifs: { notification.Notification } = {}

    -- ...
    local err = ""
    local ok, notifs_ = xpcall(function()
        return psql.macros.query_rows(
            "SELECT * FROM p_notifications WHERE owner = $1 ORDER BY created DESC LIMIT $2 OFFSET $3",
            {
                { v = owner, ty = "String" },
                { v = batch, ty = "i64" },
                { v = batch * page, ty = "i64" },
            },
            notif_read_fields
        )
    end, function(e)
        err = e
    end)

    if not ok then
        return Result.Err(general.error("DatabaseError", err))
    end

    -- ...
    for _, p in pairs(notifs_) do
        array.push(notifs, (read_row_as_notif(p) :: Result.Ok<notification.Notification>):unwrap())
    end

    return Result.Ok(notifs)
end

function notifs.create_notif(
    data: notification.Notification
): Result.Result<notification.Notification, general.Error<any>>
    -- get owner
    local owner = users.get_user_by_id(data.owner)

    if owner.is_err then
        return Result.Err(owner:unwrap_err())
    end

    local owner = owner:unwrap()

    -- ...
    local ok, _: string? = pcall(function()
        psql.macros.execute("INSERT INTO p_notifications VALUES ($1, $2, $3, $4, $5)", {
            { v = data.id, ty = "String" },
            { v = data.created, ty = "i64" },
            { v = data.owner, ty = "String" },
            { v = data.content, ty = "String" },
            { v = data.href, ty = "String" },
        })
    end)

    if not ok then
        return Result.Err(general.error("DatabaseError", nil))
    end

    users.incr_user_notifications(owner.id)
    return Result.Ok(data)
end

function notifs.delete_notification(id: string, as_user: user.User): Result.Result<nil, general.Error<any>>
    local y = notifs.get_notif_by_id(id)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    local y = y:unwrap()

    if as_user.id ~= y.owner then
        return Result.Err(general.error("NotAllowed", nil))
    end

    -- ...
    local ok, _: string? = pcall(function()
        psql.macros.execute("DELETE FROM p_notifications WHERE id = $1", {
            { v = y.id, ty = "String" },
        })
    end)

    if not ok then
        return Result.Err(general.error("DatabaseError", nil))
    end

    -- return
    cache_clear_notif(y)
    users.decr_user_notifications(as_user.id)

    return Result.Ok(nil)
end

return notifs
