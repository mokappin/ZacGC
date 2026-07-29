local lstring = string

local Result = require("@collections/Result")
local array = require("@webc/array")
local ccfg = require("@webc/sql_common")
local json = require("@webc/json")
local psql = require("@webc/psql")
local redis = require("@webc/redis")
local string = require("@webc/string")
local tools = require("@webc/tools")

local general = require("../general")
local user = require("../model/user")

local users = {}

function users.create_table(): ()
    for _, x in
        pairs(lstring.split(
            [[
            CREATE TABLE IF NOT EXISTS p_users (
                id TEXT NOT NULL PRIMARY KEY,
                created BIGINT NOT NULL,
                username TEXT NOT NULL,
                password TEXT NOT NULL,
                salt TEXT NOT NULL,
                sessions TEXT NOT NULL,
                permissions TEXT NOT NULL,
                banned INT NOT NULL,
                ban_reason TEXT NOT NULL,
                settings TEXT NOT NULL,
                notification_count INT NOT NULL,
                badges TEXT NOT NULL,
                pastes INT NOT NULL
            );
            ALTER TABLE p_users ADD COLUMN IF NOT EXISTS notification_count INT NOT NULL DEFAULT 0;
            ALTER TABLE p_users ADD COLUMN IF NOT EXISTS badges TEXT NOT NULL DEFAULT '[]';
            ALTER TABLE p_users ADD COLUMN IF NOT EXISTS pastes INT NOT NULL DEFAULT 0;
            ]],
            ";"
        ))
    do
        psql.macros.execute(x, {})
    end
end

local user_read_fields: ccfg.SqlReadColsAs = {
    { key = "id", ty = "String" },
    { key = "created", ty = "i64" },
    { key = "username", ty = "String" },
    { key = "password", ty = "String" },
    { key = "salt", ty = "String" },
    { key = "sessions", ty = "String" },
    { key = "permissions", ty = "String" },
    { key = "banned", ty = "i32" },
    { key = "ban_reason", ty = "String" },
    { key = "settings", ty = "String" },
    { key = "notification_count", ty = "i32" },
    { key = "badges", ty = "String" },
    { key = "pastes", ty = "i32" },
}

function read_row_as_user(row: Result.Result<{ [string]: any }, string>): Result.Result<user.User, general.Error<any>>
    if row.is_err then
        return Result.Err(general.error("UserNotFound", row:unwrap_err()))
    end

    local row = row:unwrap()
    return Result.Ok({
        id = row.id,
        created = row.created,
        username = row.username,
        password = row.password,
        salt = row.salt,
        sessions = json.deserialize(row.sessions),
        permissions = json.deserialize(row.permissions),
        banned = if row.banned == 1 then true else false,
        ban_reason = row.ban_reason,
        settings = json.deserialize(row.settings),
        notification_count = row.notification_count,
        badges = json.deserialize(row.badges),
        pastes = row.pastes,
    })
end

function cache_clear_user(user: user.User): ()
    redis.remove(`psng.user:{user.id}`)
    redis.remove(`psng.user:{user.username}`)
end

function users.get_user_by_id(id: string): Result.Result<user.User, general.Error<any>>
    local redis_user = redis.get(`psng.user:{id}`)
    if redis_user then
        return Result.Ok(json.deserialize(redis_user))
    end

    -- attempt to pull
    local res = Result.rpcall(function()
        return psql.macros.query_row(
            "SELECT * FROM p_users WHERE id = $1 LIMIT 1",
            { { v = id, ty = "String" } },
            user_read_fields
        )
    end)

    if res.is_err then
        return Result.Err(general.error("General", res:unwrap_err()))
    end

    local user = read_row_as_user(res)

    -- return
    if user.is_ok then
        redis.set(`psng.user:{id}`, json.serialize(user:unwrap()))
    end

    return user
end

function users.get_user_by_username(username: string): Result.Result<user.User, general.Error<any>>
    username = username:lower()

    local redis_user = redis.get(`psng.user:{username}`)
    if redis_user then
        return Result.Ok(json.deserialize(redis_user))
    end

    -- attempt to pull
    local res = Result.rpcall(function()
        return psql.macros.query_row(
            "SELECT * FROM p_users WHERE username = $1 LIMIT 1",
            { { v = username, ty = "String" } },
            user_read_fields
        )
    end)

    if res.is_err then
        return Result.Err(general.error("UserNotFound", res:unwrap_err()))
    end

    local user = read_row_as_user(res)

    -- return
    if user.is_ok then
        redis.set(`psng.user:{username}`, json.serialize(user:unwrap()))
    end

    return user
end

function users.get_user_by_token(token: string): Result.Result<user.User, general.Error<any>>
    local r = Result.rpcall(function()
        return psql.macros.query_row(
            "SELECT * FROM p_users WHERE sessions LIKE $1 LIMIT 1",
            { { v = `%{tools.sha256(token)}%`, ty = "String" } },
            user_read_fields
        )
    end)

    if r.is_err then
        return Result.Err(general.error("DatabaseError", r:unwrap_err()))
    end

    return read_row_as_user(r)
end

function users.get_users_by_query(
    query: string,
    batch: number,
    page: number
): Result.Result<{ user.User }, general.Error<any>>
    local users: { user.User } = {}

    -- ...
    local users_ = Result.rpcall(function()
        return psql.macros.query_rows(
            "SELECT * FROM p_users WHERE username LIKE $1 ORDER BY created DESC LIMIT $2 OFFSET $3",
            {
                { v = `%{query}%`, ty = "String" },
                { v = batch, ty = "i64" },
                { v = batch * page, ty = "i64" },
            },
            user_read_fields
        )
    end)

    if users_.is_err then
        return Result.Err(general.error("DatabaseError", users_:unwrap_err()))
    end

    -- ...
    for _, u in pairs(users_:unwrap()) do
        array.push(users, (read_row_as_user(Result.Ok(u)) :: Result.Ok<user.User>):unwrap())
    end

    return Result.Ok(users)
end

function users.create_user(data: user.User): Result.Result<user.User, general.Error<any>>
    if #string.trim(data.username) < 2 then
        return Result.Err(general.error("DataTooShort", "username"))
    elseif #string.trim(data.username) > 32 then
        return Result.Err(general.error("DataTooLong", "username"))
    end

    if string.regex_does_match(general.NAME_REGEX, data.username) then
        return Result.Err(general.error("InvalidCharacters", "username"))
    end

    data.username = data.username:lower()

    -- check if username is already in use
    if users.get_user_by_username(data.username).is_ok then
        return Result.Err(general.error("GeneralInUse", "username"))
    end

    -- ...
    local res = Result.rpcall(function()
        return psql.macros.execute(
            "INSERT INTO p_users VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)",
            {
                { v = data.id, ty = "String" },
                { v = data.created, ty = "i64" },
                { v = data.username, ty = "String" },
                { v = data.password, ty = "String" },
                { v = data.salt, ty = "String" },
                { v = json.serialize(data.sessions), ty = "String" },
                { v = json.serialize(data.permissions), ty = "String" },
                { v = if data.banned == true then 1 else 0, ty = "i32" },
                { v = data.ban_reason, ty = "String" },
                { v = json.serialize(data.settings), ty = "String" },
                { v = data.notification_count, ty = "i32" },
                { v = json.serialize(data.badges), ty = "String" },
                { v = data.pastes, ty = "i32" },
            }
        )
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    return Result.Ok(data)
end

function users.update_user_password(
    uid: string,
    old_password: string,
    new_password: string,
    as_user: user.User
): Result.Result<nil, general.Error<any>>
    local y = users.get_user_by_id(uid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    local is_staff = array.contains(as_user.permissions, "ManageUsers" :: user.UserPermission)

    if not is_staff and as_user.id ~= uid then
        return Result.Err(general.error("NotAllowed", nil))
    end

    -- check old
    if not is_staff then
        if tools.sha256(old_password .. y:unwrap().salt) ~= y:unwrap().password then
            return Result.Err(general.error("NotAllowed", nil))
        end
    end

    -- ...
    local new_salt = tools.salt()
    local hashed = tools.sha256(new_password .. new_salt)

    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_users SET password = $1, salt = $2 WHERE id = $3", {
            { v = hashed, ty = "String" },
            { v = new_salt, ty = "String" },
            { v = uid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    cache_clear_user(y:unwrap())
    return Result.Ok(nil)
end

local USERNAME_CHANGE_WAIT_TIME: number = 604800000 -- 1 week
function users.update_user_username(uid: string, x: string, as_user: user.User): Result.Result<nil, general.Error<any>>
    if #string.trim(x) < 2 then
        return Result.Err(general.error("DataTooShort", "username"))
    elseif #string.trim(x) > 32 then
        return Result.Err(general.error("DataTooLong", "username"))
    end

    if string.regex_does_match(general.NAME_REGEX, x) then
        return Result.Err(general.error("InvalidCharacters", "username"))
    end

    if not array.contains(as_user.permissions, "ManageUsers" :: user.UserPermission) and as_user.id ~= uid then
        return Result.Err(general.error("NotAllowed", nil))
    end

    x = x:lower()

    -- pull user
    local y = users.get_user_by_id(uid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    local y = y:unwrap()

    -- check if username is already in use
    if users.get_user_by_username(x).is_ok then
        return Result.Err(general.error("GeneralInUse", "username"))
    end

    -- ...
    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_users SET username = $1 WHERE id = $2", {
            { v = x, ty = "String" },
            { v = uid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    -- return
    cache_clear_user(y)
    return Result.Ok(nil)
end

function users.update_user_banned(uid: string, x: boolean, as_user: user.User): Result.Result<nil, general.Error<any>>
    local y = users.get_user_by_id(uid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    if not array.contains(as_user.permissions, "ManageUsers" :: user.UserPermission) then
        return Result.Err(general.error("NotAllowed", nil))
    end

    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_users SET banned = $1 WHERE id = $2", {
            { v = if x then 1 else 0, ty = "i32" },
            { v = uid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    -- return
    cache_clear_user(y:unwrap())
    return Result.Ok(nil)
end

function users.update_user_ban_reason(
    uid: string,
    x: string,
    as_user: user.User
): Result.Result<nil, general.Error<any>>
    local y = users.get_user_by_id(uid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    if not array.contains(as_user.permissions, "ManageUsers" :: user.UserPermission) then
        return Result.Err(general.error("NotAllowed", nil))
    end

    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_users SET ban_reason = $1 WHERE id = $2", {
            { v = x, ty = "String" },
            { v = uid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    -- return
    cache_clear_user(y:unwrap())
    return Result.Ok(nil)
end

function users.update_user_settings(
    uid: string,
    x: user.UserSettings,
    as_user: user.User
): Result.Result<nil, general.Error<any>>
    local y = users.get_user_by_id(uid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    if not array.contains(as_user.permissions, "ManageUsers" :: user.UserPermission) and as_user.id ~= uid then
        return Result.Err(general.error("NotAllowed", nil))
    end

    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_users SET settings = $1 WHERE id = $2", {
            { v = json.serialize(x), ty = "String" },
            { v = uid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    -- return
    cache_clear_user(y:unwrap())
    return Result.Ok(nil)
end

function users.update_user_sessions(
    uid: string,
    x: { user.UserSessionValue },
    as_user: user.User
): Result.Result<nil, general.Error<any>>
    local y = users.get_user_by_id(uid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    if not array.contains(as_user.permissions, "ManageUsers" :: user.UserPermission) and as_user.id ~= uid then
        return Result.Err(general.error("NotAllowed", nil))
    end

    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_users SET sessions = $1 WHERE id = $2", {
            { v = json.serialize(x), ty = "String" },
            { v = uid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    -- return
    cache_clear_user(y:unwrap())
    return Result.Ok(nil)
end

function users.update_user_badges(
    uid: string,
    x: { user.UserBadge },
    as_user: user.User
): Result.Result<nil, general.Error<any>>
    local y = users.get_user_by_id(uid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    if not array.contains(as_user.permissions, "ManageUsers" :: user.UserPermission) then
        return Result.Err(general.error("NotAllowed", nil))
    end

    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_users SET badges = $1 WHERE id = $2", {
            { v = json.serialize(x), ty = "String" },
            { v = uid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    -- return
    cache_clear_user(y:unwrap())
    return Result.Ok(nil)
end

function users.update_user_permissions(
    uid: string,
    x: { user.UserPermission },
    as_user: user.User
): Result.Result<nil, general.Error<any>>
    local y = users.get_user_by_id(uid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    if not array.contains(as_user.permissions, "Administrator" :: user.UserPermission) and as_user.id ~= uid then
        return Result.Err(general.error("NotAllowed", nil))
    end

    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_users SET permissions = $1 WHERE id = $2", {
            { v = json.serialize(x), ty = "String" },
            { v = uid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    -- return
    cache_clear_user(y:unwrap())
    return Result.Ok(nil)
end

function users.incr_user_notifications(uid: string): Result.Result<nil, general.Error<any>>
    local y = users.get_user_by_id(uid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_users SET notification_count = notification_count + 1 WHERE id = $1", {
            { v = uid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    -- return
    cache_clear_user(y:unwrap())
    return Result.Ok(nil)
end

function users.decr_user_notifications(uid: string): Result.Result<nil, general.Error<any>>
    local y = users.get_user_by_id(uid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_users SET notification_count = notification_count - 1 WHERE id = $1", {
            { v = uid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    -- return
    cache_clear_user(y:unwrap())
    return Result.Ok(nil)
end

function users.incr_user_pastes(uid: string): Result.Result<nil, general.Error<any>>
    local y = users.get_user_by_id(uid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_users SET pastes = pastes + 1 WHERE id = $1", {
            { v = uid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    -- return
    cache_clear_user(y:unwrap())
    return Result.Ok(nil)
end

function users.decr_user_pastes(uid: string): Result.Result<nil, general.Error<any>>
    local y = users.get_user_by_id(uid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_users SET pastes = pastes - 1 WHERE id = $1", {
            { v = uid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    -- return
    cache_clear_user(y:unwrap())
    return Result.Ok(nil)
end

function users.delete_user(uid: string, as_user: user.User, password: string): Result.Result<nil, general.Error<any>>
    local y = users.get_user_by_id(uid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    local y = y:unwrap()

    -- check general permissions
    if
        (not array.contains(as_user.permissions, "ManageUsers" :: user.UserPermission) and as_user.id ~= uid)
        or array.contains(y.permissions, "Administrator" :: user.UserPermission)
    then
        return Result.Err(general.error("NotAllowed", nil))
    end

    -- check password
    if
        tools.sha256(password .. y.salt) ~= y.password
        and not array.contains(as_user.permissions, "ManageUsers" :: user.UserPermission)
    then
        return Result.Err(general.error("NotAllowed", nil))
    end

    -- delete
    local res = Result.rpcall(function()
        return psql.macros.execute("DELETE FROM p_users WHERE id = $1", {
            { v = uid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    -- return
    cache_clear_user(y)
    return Result.Ok(nil)
end

function users.get_user_from_cookie(c: { [string]: string }): Result.Result<user.User, general.Error<any>>
    if not c["__Secure-pastry-token"] then
        return Result.Err(general.error("UserNotFound", nil))
    end

    return users.get_user_by_token(c["__Secure-pastry-token"])
end

return users
