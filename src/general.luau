local features = require("@webc/features")

export type ErrorName =
    "UserNotFound"
    | "DatabaseError"
    | "UsernameChangedTooRecently"
    | "DataTooLong"
    | "DataTooShort"
    | "GeneralInUse"
    | "InvalidCharacters"
    | "PasteNotFound"
    | "NotAllowed"
    | "EmptyBody"
    | "General"

export type Error<T> = {
    name: ErrorName,
    value: T,
}

local general = {
    NAME_REGEX = "[^\\w_\\-\\.,!]+",
}

function general.error_msg<T>(err: Error<T>): string
    return features.match(err.name, {
        ["UserNotFound"] = "Could not find requested user",
        ["DatabaseError"] = "Unknown database error occurred",
        ["UsernameChangedTooRecently"] = "You've changed your username too recently",
        ["DataTooLong"] = `Given {err.value} is too long`,
        ["DataTooShort"] = `Given {err.value} is too short`,
        ["GeneralInUse"] = `Given {err.value} is already in use`,
        ["InvalidCharacters"] = `Given {err.value} contains invalid characters`,
        ["PasteNotFound"] = "Could not find requested paste",
        ["NotAllowed"] = "You are not allowed to do this",
        ["EmptyBody"] = "Body cannot be empty for this request",
        ["General"] = err.value,
        _ = function()
            features.throw(`Unknown error name: {err.name}`)
        end,
    })
end

function general.error<T>(err: ErrorName, value): Error<T>
    return { name = err, value = value }
end

return general
