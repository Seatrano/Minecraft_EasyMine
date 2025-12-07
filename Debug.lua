local DeviceFinder = require("helper.getDevices")
local finder = DeviceFinder.new()

finder:openModem()
local mon = finder:getMonitor()

mon.clear()
mon.setCursorPos(1, 1)

print("Debug Computer running...")

local width, height = mon.getSize()
local logLines = {}

while true do
    local id, messageStr = rednet.receive("Debug")

    -- Nachricht deserialisieren
    local success, message = pcall(textutils.unserialize, messageStr)
    if not success then
        message = {source="unknown", debug=messageStr}
    end

    local debugMsg = (message.source or "?") .. ": " .. (message.debug or "?")
    table.insert(logLines, debugMsg)

    -- Nur Monitorhöhe anzeigen
    if #logLines > height then
        table.remove(logLines, 1)
    end

    -- Monitor aktualisieren
    mon.clear()
    for i, line in ipairs(logLines) do
        mon.setCursorPos(1, i)
        mon.write(line)
    end
end
