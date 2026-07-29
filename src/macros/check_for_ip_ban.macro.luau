return function(_)
    return [[
    local MACRO_ip_ban = if ip_bans ~= nil then users.get_ip_ban_by_ip(h[_G.state.config.real_ip_header] or "") else _ip_bans.get_ip_ban_by_ip(h[_G.state.config.real_ip_header] or "")

    if MACRO_ip_ban.is_ok then
        return helpers.api_return(false, general.error_msg(general.error("NotAllowed", nil)), nil)
    end
    ]]
end
