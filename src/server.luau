local http = require("@webc/http")
local http_util = require("@webc/http_util")

local api = require("./routes/api")
local general = require("./general")
local pages = require("./routes/pages")
local pages_helper = require("./routes/pages/helpers")

local config = require("./config")
local templates = require("./templates")

-- create global state
local global_state = {
    config = (config.read() :: any):unwrap(),
}

_G.state = global_state

-- load templates
templates.build("./templates_src")

-- ...
return function(proc: http.SplitProcess)
    -- this CANNOT return anything because this is run on a different lua instance!
    proc.fallback(function(_): http.Response
        return pages_helper.return_error(general.error("General", "404: Not Found"), {})
    end)

    api(proc)
    pages(proc)

    proc.route("GET", "/public/{*path}", http_util.fs_mount("./public"))
end
