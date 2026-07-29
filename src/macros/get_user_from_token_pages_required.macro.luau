return function()
    return [[
    local MACRO_requesting_user = users.get_user_from_cookie(c)

    if MACRO_requesting_user.is_err then
        return helpers.return_error(MACRO_requesting_user:unwrap_err(), helpers.default_context(option.None()))
    end

    local user = MACRO_requesting_user.value
    ]]
end
