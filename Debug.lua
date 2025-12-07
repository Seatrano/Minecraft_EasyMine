local DeviceFinder = require("helper.DeviceFinder")
local finder = DeviceFinder.new()

finder:openModem()
local mon = finder:getMonitor()

mon.clear()
mon.setCursorPos(1, 1)
mon.write("Warte auf Daten...")


local PROTOCOL = "Debug"

print("Debug Computer running...")

while true do
    local sender, msg, proto = rednet.receive("Debug")

    if proto == PROTOCOL then
        mon.clear()
        mon.setCursorPos(1,1)
        mon.write("DEBUG DATA:")
        mon.setCursorPos(1,2)
        mon.write(msg.debug or "no debug info")
    end
end
