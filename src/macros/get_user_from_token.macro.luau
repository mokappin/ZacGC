return function()
    return [[
    local MACRO_requesting_user = if users ~= nil then users.get_user_from_cookie(c) else _users.get_user_from_cookie(c)

    if MACRO_requesting_user.is_err then
        return helpers.api_return(false, general.error_msg(MACRO_requesting_user:unwrap_err()), nil)
    end

    local user = MACRO_requesting_user.value
    ]]
end
