local DeviceFinder = require("helper.getDevices")
local finder = DeviceFinder.new()

finder:openModem()
local mon = finder:getMonitor()

mon.clear()
mon.setCursorPos(1, 1)

print("Debug Computer running...")

-- Monitorgröße ermitteln
local width, height = mon.getSize()
local logLines = {} -- speichert die Nachrichten

while true do
    local id, message = rednet.receive("Debug")
    
    print("Received message from ID: " .. id .. with .. message)
    print("Message content: " .. textutils.serialize(message))

    table.insert(logLines, textutils.serialize(sender) .. " " .. textutils.serialize(msg.debug))

    -- Sicherstellen, dass nur so viele Zeilen wie Monitorhöhe angezeigt werden
    if #logLines > height then
        table.remove(logLines, 1) -- älteste Zeile entfernen
    end

    -- Monitor aktualisieren
    mon.clear()
    for i, line in ipairs(logLines) do
        mon.setCursorPos(1, i)
        mon.write(line)
    end

end
