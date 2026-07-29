local http = require("@webc/http")
local http_util = require("@webc/http_util")

local mod = {}

function mod.json(body: { [any]: any }): http.Response
    return http_util.json(body)
end

function mod.api_return<T>(ok: boolean, message: string, payload: T): http.Response
    return mod.json({
        ok = ok,
        message = message,
        payload = payload,
    })
end

function mod.json_headers(body: { [any]: any }, headers: { [string]: string }): http.Response
    local res = http_util.json(body)

    for k, v in headers do
        res:header(k, v)
    end

    return res
end

function mod.api_return_headers<T>(ok: boolean, message: string, payload: T, headers: { [string]: string }): http.Response
    return mod.json_headers({
        ok = ok,
        message = message,
        payload = payload,
    }, headers)
end

return mod
