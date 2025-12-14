-- CommandCenter.lua
-- Sendet Befehle an den Master, der sie an alle Turtles weiterleitet

local DeviceFinder = require("helper.getDevices")
local finder = DeviceFinder.new()
finder:openModem()

print("=" .. string.rep("=", 50) .. "=")
print("  TURTLE COMMAND CENTER")
print("=" .. string.rep("=", 50) .. "=")
print("")
print("Verfuegbare Befehle:")
print("  1) Return to Base    - Alle Turtles zurueck zum Startpunkt")
print("  2) Resume Mining     - Mining fortsetzen")
print("  3) Pause Mining      - Mining pausieren")
print("  4) Status Report     - Status aller Turtles anfordern")
print("  5) Emergency Stop    - Sofortiger Stopp aller Turtles")
print("  6) Refuel All        - Alle Turtles tanken lassen")
print("  7) Unload All        - Alle Inventare entleeren")
print("  q) Beenden")
print("")

local commands = {
    ["1"] = {cmd = "returnToBase", desc = "Return to Base"},
    ["2"] = {cmd = "resumeMining", desc = "Resume Mining"},
    ["3"] = {cmd = "pauseMining", desc = "Pause Mining"},
    ["4"] = {cmd = "statusReport", desc = "Status Report"},
    ["5"] = {cmd = "emergencyStop", desc = "Emergency Stop"},
    ["6"] = {cmd = "refuelAll", desc = "Refuel All"},
    ["7"] = {cmd = "unloadAll", desc = "Unload All"}
}

local function sendCommand(cmd, params)
    local message = {
        type = "command",
        command = cmd,
        params = params or {},
        timestamp = os.epoch("utc")
    }
    
    rednet.broadcast(textutils.serialize(message), "TURTLE_CMD")
    print("[SENT] Command: " .. cmd)
    print("")
end

while true do
    write("Enter command number (or 'q' to quit): ")
    local input = read()
    
    if input == "q" or input == "Q" then
        print("Exiting Command Center...")
        break
    end
    
    local cmdData = commands[input]
    if cmdData then
        print("")
        print("Sending: " .. cmdData.desc)
        
        -- Spezielle Parameter für bestimmte Befehle
        local params = {}
        
        if input == "1" then
            write("Wait at base? (y/n): ")
            local wait = read()
            params.waitAtBase = (wait:lower() == "y")
        end
        
        sendCommand(cmdData.cmd, params)
        
        print("Command sent to all turtles!")
        print("")
    else
        print("Invalid command!")
        print("")
    end
end

print("")
print("Command Center closed.")