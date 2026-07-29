local http = require("@webc/http")
local http_util = require("@webc/http_util")
local option = require("@collections/Option")
local result = require("@collections/Result")
local string = require("@webc/string")

local general = require("../../general")
local user = require("../../model/user")

export type PaginatedQuery = {
    page: number,
}

export type SearchedQuery = {
    page: number,
    query: string,
}

function unwrap_or_nil(o: option.Option<any>): any?
    return if o.is_some then o:unwrap() else nil
end

local mod = {}

function mod.html(body: string): http.Response
    return http_util.html(body)
end

function mod.html_headers(body: string, headers: { [string]: string }): http.Response
    local res = http_util.html(body)

    for k, v in headers do
        res:header(k, v)
    end

    return res
end

function mod.return_error(err: general.Error<any>, ctx: { [any]: any }): http.Response
    ctx.error = tostring(general.error_msg(err))
    return http_util.tmpl("error.html", ctx)
end

function mod.default_context(user: option.Option<user.User>): { [any]: any }
    return {
        ["user"] = unwrap_or_nil(user),
        ["config"] = _G.state.config,
    }
end

function mod.result_to_option<T>(r: result.Result<T, any>): option.Option<T>
    return if r.is_ok then option.Some(r:unwrap()) else option.None()
end

function mod.remove_script_tags(haystack: string): string
    return string.replace(string.replace(haystack, "</script>", "&lt;/script&gt;"), "<script>", "&lt;script&gt;")
end

return mod
