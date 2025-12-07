local monitorFunctions = {}
monitorFunctions.__index = monitorFunctions

local function padRight(str, length)
    str = tostring(str or "?")
    if #str < length then
        return string.rep(" ", length - #str) .. str
    else
        return str
    end
end

local function padLeft(str, length)
    str = tostring(str or "?")
    if #str < length then
        return str .. string.rep(" ", length - #str)
    else
        return str
    end
end

return monitorFunctions