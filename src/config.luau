local Option = require("@collections/Option")
local ccfg = require("@webc/sql_common")
local features = require("@webc/features")
local fs = require("@webc/fs")
local toml = require("@webc/toml")

export type PastryConfig = {
    name: string,
    port: number,
    real_ip_header: string,
    database: ccfg.CommonConfig,
    issuestack_claims_project_id: number,
    issuestack_reports_project_id: number,
    reclaim_help_guide_url: string,
}

local config = {}

function config.read(): Option.Option<PastryConfig>
    if not fs.exists("./app.toml") then
        features.throw("Config file does not exist. Please create `app.toml`.")
        return Option.None()
    end

    return Option.Some(toml.deserialize(fs.read("./app.toml")))
end

return config
