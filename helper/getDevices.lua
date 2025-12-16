local DeviceFinder = {}
DeviceFinder.__index = DeviceFinder

local sides = {"top", "bottom", "left", "right", "front", "back"}

function DeviceFinder.new()
    return setmetatable({}, DeviceFinder)
end

function DeviceFinder:find(typeName)
    for _, side in ipairs(sides) do
        if peripheral.getType(side) == typeName then
            return side
        end
    end
    print("No peripheral of type '" .. typeName .. "' found.")
    return nil
end

function DeviceFinder:openModem()
    local side = self:find("modem")
    if side then
        rednet.open(side)
    end
    return side
end

function DeviceFinder:getMonitor()
    local side = self:find("monitor")
    if not side then
        return nil
    end
    return peripheral.wrap(side)
end

return DeviceFinder
