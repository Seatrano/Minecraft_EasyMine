local monitorFunctions = {}
monitorFunctions.__index = monitorFunctions

function monitorFunctions.new()
    return setmetatable({}, monitorFunctions)
end

function monitorFunctions:padRight(str, length)
    str = tostring(str or "?")
    if #str < length then
        return string.rep(" ", length - #str) .. str
    else
        return str
    end
end

function monitorFunctions:padLeft(str, length)
    str = tostring(str or "?")
    if #str < length then
        return str .. string.rep(" ", length - #str)
    else
        return str
    end
end

return monitorFunctions