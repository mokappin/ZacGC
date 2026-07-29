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
local paste = require("../model/paste")
local user = require("../model/user")
local users = require("./users")

local pastes = {}

function pastes.create_table(): ()
    for _, x in
        pairs(lstring.split(
            [[
            CREATE TABLE IF NOT EXISTS p_pastes (
                id TEXT NOT NULL PRIMARY KEY,
                created BIGINT NOT NULL,
                edited BIGINT NOT NULL,
                owner TEXT NOT NULL REFERENCES p_users(id) ON DELETE CASCADE,
                slug TEXT NOT NULL,
                html TEXT NOT NULL,
                css TEXT NOT NULL,
                settings TEXT NOT NULL,
                views INT NOT NULL,
                is_locked INT NOT NULL
            );
            ALTER TABLE p_pastes ADD COLUMN IF NOT EXISTS views INT NOT NULL DEFAULT 0;
            ALTER TABLE p_pastes ADD COLUMN IF NOT EXISTS is_locked INT NOT NULL DEFAULT 0;
            ]],
            ";"
        ))
    do
        psql.macros.execute(x, {})
    end
end

local pastes_read_fields: ccfg.SqlReadColsAs = {
    { key = "id", ty = "String" },
    { key = "created", ty = "i64" },
    { key = "edited", ty = "i64" },
    { key = "owner", ty = "String" },
    { key = "slug", ty = "String" },
    { key = "html", ty = "String" },
    { key = "css", ty = "String" },
    { key = "settings", ty = "String" },
    { key = "views", ty = "i32" },
    { key = "is_locked", ty = "i32" },
}

function read_row_as_paste(
    row: Result.Result<{ [string]: any }, string>
): Result.Result<paste.Paste, general.Error<any>>
    if row.is_err then
        return Result.Err(general.error("PasteNotFound", row:unwrap_err()))
    end

    local row = row:unwrap()
    return Result.Ok({
        id = row.id,
        created = row.created,
        edited = row.edited,
        owner = row.owner,
        slug = row.slug,
        html = row.html,
        css = row.css,
        settings = json.deserialize(row.settings),
        views = row.views,
        is_locked = row.is_locked == 1,
    })
end

function cache_clear_paste(paste: paste.Paste): ()
    redis.remove(`psng.paste:{paste.id}`)
    redis.remove(`psng.paste:{paste.slug}`)
end

function pastes.get_paste_by_id(id: string): Result.Result<paste.Paste, general.Error<any>>
    local redis_paste = redis.get(`psng.paste:{id}`)
    if redis_paste then
        return Result.Ok(json.deserialize(redis_paste))
    end

    -- attempt to pull
    local res = Result.rpcall(function()
        return psql.macros.query_row(
            "SELECT * FROM p_pastes WHERE id = $1 LIMIT 1",
            { { v = id, ty = "String" } },
            pastes_read_fields
        )
    end)

    if res.is_err then
        return Result.Err(general.error("PasteNotFound", res:unwrap_err()))
    end

    local paste = read_row_as_paste(res)

    -- return
    if paste.is_ok then
        redis.set(`psng.paste:{id}`, json.serialize(paste:unwrap()))
    end

    return paste
end

function pastes.get_paste_by_slug(slug: string): Result.Result<paste.Paste, general.Error<any>>
    slug = slug:lower()

    local redis_paste = redis.get(`psng.paste:{slug}`)
    if redis_paste then
        return Result.Ok(json.deserialize(redis_paste))
    end

    -- attempt to pull
    local res = Result.rpcall(function()
        return psql.macros.query_row(
            "SELECT * FROM p_pastes WHERE slug = $1 LIMIT 1",
            { { v = slug, ty = "String" } },
            pastes_read_fields
        )
    end)

    if res.is_err then
        return Result.Err(general.error("PasteNotFound", res:unwrap_err()))
    end

    local paste = read_row_as_paste(res)

    -- return
    if paste.is_ok then
        redis.set(`psng.paste:{slug}`, json.serialize(paste:unwrap()))
    end

    return paste
end

function pastes.get_pastes_by_owner(
    owner: string,
    batch: number,
    page: number
): Result.Result<{ paste.Paste }, general.Error<any>>
    local pastes: { paste.Paste } = {}

    -- ...
    local pastes_ = Result.rpcall(function()
        return psql.macros.query_rows(
            "SELECT * FROM p_pastes WHERE owner = $1 ORDER BY created DESC LIMIT $2 OFFSET $3",
            {
                { v = owner, ty = "String" },
                { v = batch, ty = "i64" },
                { v = batch * page, ty = "i64" },
            },
            pastes_read_fields
        )
    end)

    if pastes_.is_err then
        return Result.Err(general.error("DatabaseError", pastes_:unwrap_err()))
    end

    -- ...
    for _, p in pairs(pastes_:unwrap()) do
        -- it might seem a little cumbersome to have to cast to Result.Ok, but it
        -- ensures you're *really* sure you want to unwrap... which we are here
        array.push(pastes, (read_row_as_paste(Result.Ok(p)) :: Result.Ok<paste.Paste>):unwrap())
    end

    return Result.Ok(pastes)
end

function pastes.get_paste_count_by_owner_period(
    owner: string,
    period: number
): Result.Result<number, general.Error<any>>
    local delta = tools.unix_epoch_timestamp() - period

    local res = Result.rpcall(function()
        return psql.macros.query_row("SELECT COUNT(id) FROM p_pastes WHERE owner = $1 AND created >= $2", {
            { v = owner, ty = "String" },
            { v = delta, ty = "i64" },
        }, {
            { key = "count", ty = "i64" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    return Result.Ok(res:unwrap().count)
end

function pastes.get_pastes_by_query(
    query: string,
    batch: number,
    page: number
): Result.Result<{ paste.Paste }, general.Error<any>>
    local pastes: { paste.Paste } = {}

    -- ...
    local pastes_ = Result.rpcall(function()
        return psql.macros.query_rows(
            "SELECT * FROM p_pastes WHERE html LIKE $1 OR slug LIKE $1 ORDER BY created DESC LIMIT $2 OFFSET $3",
            {
                { v = `%{query}%`, ty = "String" },
                { v = batch, ty = "i64" },
                { v = batch * page, ty = "i64" },
            },
            pastes_read_fields
        )
    end)

    if pastes_.is_err then
        return Result.Err(general.error("DatabaseError", pastes_:unwrap_err()))
    end

    -- ...
    for _, p in pairs(pastes_:unwrap()) do
        array.push(pastes, (read_row_as_paste(Result.Ok(p)) :: Result.Ok<paste.Paste>):unwrap())
    end

    return Result.Ok(pastes)
end

function pastes.create_paste(data: paste.Paste): Result.Result<paste.Paste, general.Error<any>>
    if #string.trim(data.slug) < 1 then
        data.slug = tools.salt()
    elseif #string.trim(data.slug) > 128 then
        return Result.Err(general.error("DataTooLong", "slug"))
    end

    if string.regex_does_match(general.NAME_REGEX, data.slug) then
        return Result.Err(general.error("InvalidCharacters", "slug"))
    end

    data.slug = data.slug:lower()

    -- check if slug is already in use
    if pastes.get_paste_by_slug(data.slug).is_ok then
        return Result.Err(general.error("GeneralInUse", "slug"))
    end

    -- ...
    local res = Result.rpcall(function()
        return psql.macros.execute("INSERT INTO p_pastes VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)", {
            { v = data.id, ty = "String" },
            { v = data.created, ty = "i64" },
            { v = data.edited, ty = "i64" },
            { v = data.owner, ty = "String" },
            { v = data.slug, ty = "String" },
            { v = data.html, ty = "String" },
            { v = data.css, ty = "String" },
            { v = json.serialize(data.settings), ty = "String" },
            { v = data.views, ty = "i32" },
            { v = if data.is_locked then 1 else 0, ty = "i32" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    -- incr user pastes
    local x = users.incr_user_pastes(data.owner)

    if x.is_err then
        return Result.Err(x:unwrap_err())
    end

    -- ...
    return Result.Ok(data)
end

function pastes.update_paste_settings(
    pid: string,
    x: paste.PasteSettings,
    as_user: user.User
): Result.Result<nil, general.Error<any>>
    local y = pastes.get_paste_by_id(pid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    local y = y:unwrap()

    if not array.contains(as_user.permissions, "ManagePastes" :: user.UserPermission) and as_user.id ~= y.owner then
        return Result.Err(general.error("NotAllowed", nil))
    end

    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_pastes SET settings = $1, edited = $2 WHERE id = $3", {
            { v = json.serialize(x), ty = "String" },
            { v = tools.unix_epoch_timestamp(), ty = "i64" },
            { v = pid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    -- return
    cache_clear_paste(y)
    return Result.Ok(nil)
end

function pastes.update_paste_owner(pid: string, x: string, as_user: user.User): Result.Result<nil, general.Error<any>>
    local y = pastes.get_paste_by_id(pid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    local y = y:unwrap()

    if not array.contains(as_user.permissions, "ManagePastes" :: user.UserPermission) and as_user.id ~= y.owner then
        return Result.Err(general.error("NotAllowed", nil))
    end

    -- fetch other user
    local other_user = users.get_user_by_username(x)

    if other_user.is_err then
        return other_user
    end

    local other_user = other_user:unwrap()

    -- ...
    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_pastes SET owner = $1 WHERE id = $2", {
            { v = other_user.id, ty = "String" },
            { v = pid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", nil))
    end

    -- return
    cache_clear_paste(y)
    return Result.Ok(nil)
end

function pastes.update_paste_html(pid: string, x: string, as_user: user.User): Result.Result<nil, general.Error<any>>
    local y = pastes.get_paste_by_id(pid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    if not paste.can_edit(y:unwrap(), as_user) then
        return Result.Err(general.error("NotAllowed", nil))
    end

    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_pastes SET html = $1, edited = $2 WHERE id = $3", {
            { v = x, ty = "String" },
            { v = tools.unix_epoch_timestamp(), ty = "i64" },
            { v = pid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    cache_clear_paste(y:unwrap())
    return Result.Ok(nil)
end

function pastes.update_paste_css(pid: string, x: string, as_user: user.User): Result.Result<nil, general.Error<any>>
    local y = pastes.get_paste_by_id(pid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    if not paste.can_edit(y:unwrap(), as_user) then
        return Result.Err(general.error("NotAllowed", nil))
    end

    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_pastes SET css = $1, edited = $2 WHERE id = $3", {
            { v = x, ty = "String" },
            { v = tools.unix_epoch_timestamp(), ty = "i64" },
            { v = pid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    cache_clear_paste(y:unwrap())
    return Result.Ok(nil)
end

function pastes.update_paste_content(
    pid: string,
    html: string,
    css: string,
    as_user: user.User
): Result.Result<nil, general.Error<any>>
    local y = pastes.get_paste_by_id(pid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    if not paste.can_edit(y:unwrap(), as_user) then
        return Result.Err(general.error("NotAllowed", nil))
    end

    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_pastes SET html = $1, css = $2, edited = $3 WHERE id = $4", {
            { v = html, ty = "String" },
            { v = css, ty = "String" },
            { v = tools.unix_epoch_timestamp(), ty = "i64" },
            { v = pid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    cache_clear_paste(y:unwrap())
    return Result.Ok(nil)
end

function pastes.update_paste_slug(pid: string, x: string, as_user: user.User): Result.Result<nil, general.Error<any>>
    local y = pastes.get_paste_by_id(pid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    if not paste.can_manage(y:unwrap(), as_user) then
        return Result.Err(general.error("NotAllowed", nil))
    end

    -- check for existing paste by this slug
    local xp = pastes.get_paste_by_slug(x)

    if not xp.is_err then
        return Result.Err(general.error("GeneralInUse", "slug"))
    end

    -- ...
    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_pastes SET slug = $1, edited = $2 WHERE id = $3", {
            { v = x, ty = "String" },
            { v = tools.unix_epoch_timestamp(), ty = "i64" },
            { v = pid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    cache_clear_paste(y:unwrap())
    return Result.Ok(nil)
end

function pastes.update_paste_is_locked(
    pid: string,
    x: boolean,
    as_user: user.User
): Result.Result<nil, general.Error<any>>
    local y = pastes.get_paste_by_id(pid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    local y = y:unwrap()

    if not array.contains(as_user.permissions, "ManagePastes" :: user.UserPermission) then
        return Result.Err(general.error("NotAllowed", nil))
    end

    -- ...
    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_pastes SET is_locked = $1 WHERE id = $2", {
            { v = if x then 1 else 0, ty = "i32" },
            { v = pid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    cache_clear_paste(y)

    if x then
        users.decr_user_pastes(y.owner)
    else
        users.incr_user_pastes(y.owner)
    end

    return Result.Ok(nil)
end

function pastes.incr_paste_views(uid: string): Result.Result<nil, general.Error<any>>
    local y = pastes.get_paste_by_id(uid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_pastes SET views = views + 1 WHERE id = $1", {
            { v = uid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    -- return
    cache_clear_paste(y:unwrap())
    return Result.Ok(nil)
end

function pastes.decr_paste_views(uid: string): Result.Result<nil, general.Error<any>>
    local y = pastes.get_paste_by_id(uid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    local res = Result.rpcall(function()
        return psql.macros.execute("UPDATE p_pastes SET views = views - 1 WHERE id = $1", {
            { v = uid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    -- return
    cache_clear_paste(y:unwrap())
    return Result.Ok(nil)
end

function pastes.delete_paste(uid: string, as_user: user.User): Result.Result<nil, general.Error<any>>
    local y = pastes.get_paste_by_id(uid)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    local y = y:unwrap()

    if not array.contains(as_user.permissions, "ManagePastes" :: user.UserPermission) and as_user.id ~= y.owner then
        return Result.Err(general.error("NotAllowed", nil))
    end

    local res = Result.rpcall(function()
        return psql.macros.execute("DELETE FROM p_pastes WHERE id = $1", {
            { v = uid, ty = "String" },
        })
    end)

    if res.is_err then
        return Result.Err(general.error("DatabaseError", res:unwrap_err()))
    end

    -- decr user pastes
    local x = users.decr_user_pastes(y.owner)

    if x.is_err then
        return Result.Err(x:unwrap_err())
    end

    -- return
    cache_clear_paste(y)
    return Result.Ok(nil)
end

return pastes
