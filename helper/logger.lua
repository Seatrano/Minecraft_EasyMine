local logger = {}
logger.__index = logger

function logger.new()
    return setmetatable({}, logger)
end

function logger:logDebug(source, message)
    local data = {
        source = source,
        debug = message
    }
    rednet.broadcast(data, "Debug")
end

return logger