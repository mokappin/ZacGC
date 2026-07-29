local fs = require("@webc/fs")
local globber = require("@webc/globber")
local string = require("@webc/string")
local tera = require("@webc/tera")

local templates = {}

function templates.load(path): ()
    tera.add_filter("remove_script_tags", function(x, _)
        return string.replace(x, "</script>", "&lt;/script&gt;")
    end)

    tera.add(string.replacen(path, "templates_src/", "", 1), fs.read(path))
end

function templates.build(src: string): ()
    local preload_templates = { "templates_src/components.html", "templates_src/base.html" }

    for _, f in pairs(preload_templates) do
        templates.load(f)
    end

    for _, f in pairs(globber.glob(src .. "/**/*")) do
        if fs.stat(f).is_dir then
            -- cool
            continue
        end

        templates.load(f)
    end
end

return templates
