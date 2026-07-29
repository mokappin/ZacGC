local http = require("@webc/http")
local tera = require("@webc/tera")

local helpers = require("./helpers")
local users = require("../../database/users")

local mod = {}

function mod.index_request(_, _, c, _): http.Response
    local user = helpers.result_to_option(users.get_user_from_cookie(c))
    return helpers.html(tera.render("index.html", helpers.default_context(user)))
end

function mod.register_request(_, _, c, _): http.Response
    local user = helpers.result_to_option(users.get_user_from_cookie(c))
    return helpers.html(tera.render("register.html", helpers.default_context(user)))
end

function mod.login_request(_, _, c, _): http.Response
    local user = helpers.result_to_option(users.get_user_from_cookie(c))
    return helpers.html(tera.render("login.html", helpers.default_context(user)))
end

return mod
