local Result = require("@collections/Result")
local array = require("@webc/array")
local ccfg = require("@webc/sql_common")
local psql = require("@webc/psql")

local general = require("../general")
local ip_ban = require("../model/ip_ban")
local user = require("../model/user")

local ip_bans = {}

function ip_bans.create_table(): ()
    psql.macros.execute(
        [[CREATE TABLE IF NOT EXISTS p_ip_bans (
            id TEXT NOT NULL PRIMARY KEY,
            created BIGINT NOT NULL,
            owner TEXT NOT NULL REFERENCES p_users(id) ON DELETE CASCADE,
            ip TEXT NOT NULL UNIQUE,
            reason TEXT NOT NULL
        )]],
        {}
    )
end

local ip_ban_read_fields: ccfg.SqlReadColsAs = {
    { key = "id", ty = "String" },
    { key = "created", ty = "i64" },
    { key = "user1", ty = "String" },
    { key = "ip", ty = "String" },
    { key = "reason", ty = "String" },
}

function read_row_as_ip_ban(row: { [string]: any }): Result.Result<ip_ban.IpBan, general.Error<any>>
    if row == nil then
        return Result.Err(general.error("General", "no such ip ban"))
    end

    return Result.Ok({
        id = row.id,
        created = row.created,
        owner = row.owner,
        ip = row.ip,
        reason = row.reason,
    })
end

function ip_bans.get_ip_ban_by_ip(ip: string): Result.Result<ip_ban.IpBan, general.Error<any>>
    -- attempt to pull
    local err = ""
    local ok, res = xpcall(function()
        return psql.macros.query_row(
            "SELECT * FROM p_ip_bans WHERE ip = $1 LIMIT 1",
            { { v = ip, ty = "String" } },
            ip_ban_read_fields
        )
    end, function(e)
        err = e
    end)

    if not ok then
        return Result.Err(general.error("General", "no such ip ban"))
    end

    local ip_ban = read_row_as_ip_ban(res)

    -- return
    return ip_ban
end

function ip_bans.get_ip_bans(batch: number, page: number): Result.Result<{ ip_ban.IpBan }, general.Error<any>>
    local ip_bans: { ip_ban.IpBan } = {}

    -- ...
    local err = ""
    local ok, pastes_ = xpcall(function()
        return psql.macros.query_rows("SELECT * FROM p_ip_bans ORDER BY created DESC LIMIT $1 OFFSET $2", {
            { v = batch, ty = "i64" },
            { v = batch * page, ty = "i64" },
        }, ip_ban_read_fields)
    end, function(e)
        err = e
    end)

    if not ok then
        return Result.Err(general.error("DatabaseError", err))
    end

    -- ...
    for _, p in pairs(pastes_) do
        array.push(ip_bans, (read_row_as_ip_ban(p) :: Result.Ok<ip_ban.IpBan>):unwrap())
    end

    return Result.Ok(ip_bans)
end

function ip_bans.create_ip_ban(data: ip_ban.IpBan): Result.Result<ip_ban.IpBan, general.Error<any>>
    local fail_reason = ""
    local ok, _: string? = xpcall(function()
        psql.macros.execute("INSERT INTO p_ip_bans VALUES ($1, $2, $3, $4, $5)", {
            { v = data.id, ty = "String" },
            { v = data.created, ty = "i64" },
            { v = data.owner, ty = "String" },
            { v = data.ip, ty = "String" },
            { v = data.reason, ty = "String" },
        })
    end, function(e)
        fail_reason = e
    end)

    if not ok then
        return Result.Err(general.error("DatabaseError", fail_reason))
    end

    return Result.Ok(data)
end

function ip_bans.delete_ip_ban_by_ip(ip: string, as_user: user.User): Result.Result<nil, general.Error<any>>
    local y = ip_bans.get_ip_ban_by_ip(ip)

    if y.is_err then
        return Result.Err(y:unwrap_err())
    end

    local y = y:unwrap()

    local ok, _: string? = pcall(function()
        psql.macros.execute("DELETE FROM p_ip_bans WHERE ip = $1", {
            { v = y.ip, ty = "String" },
        })
    end)

    if not ok then
        return Result.Err(general.error("DatabaseError", nil))
    end

    -- return
    return Result.Ok(nil)
end

return ip_bans
