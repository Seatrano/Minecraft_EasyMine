-- CommandCenter.lua
-- Sendet Befehle an den Master, der sie an alle Turtles weiterleitet

local DeviceFinder = require("helper.getDevices")
local finder = DeviceFinder.new()
finder:openModem()

local function drawMenu()
    term.clear()
    term.setCursorPos(1, 1)

    print("=" .. string.rep("=", 50) .. "=")
    print("  TURTLE COMMAND CENTER")
    print("=" .. string.rep("=", 50) .. "=")
    print("")
    print("Verfuegbare Befehle:")
    print("  1) Return to Base    - Alle Turtles zurueck zum Startpunkt")
    print("  2) Go Mining         - Alle Turtles starten mit dem Mining")
    print("  q) Beenden")
    print("")
end


print("=" .. string.rep("=", 50) .. "=")
print("  TURTLE COMMAND CENTER")
print("=" .. string.rep("=", 50) .. "=")
print("")
print("Verfuegbare Befehle:")
print("  1) Return to Base    - Alle Turtles zurueck zum Startpunkt")
print("  2) Go Mining         - Alle Turtles starten mit dem Mining")
print("  q) Beenden")
print("")

local commands = {
    ["1"] = {cmd = "returnToBase", desc = "Return to Base"},
    ["2"] = {cmd = "resumeMining", desc = "Go Mining"}
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

        sendCommand(cmdData.cmd)

        print("Command sent to all turtles!")
        sleep(1.5)
        drawMenu()
    else
        print("Invalid command!")
        sleep(1.5)
        drawMenu()
    end
end
