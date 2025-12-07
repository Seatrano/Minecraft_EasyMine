local sides = {"top", "bottom", "left", "right", "front", "back"}
local modemSide = nil
for _, side in ipairs(sides) do
    if peripheral.getType(side) == "modem" then
        modemSide = side
        break
    end
end

if modemSide then
    rednet.open(modemSide)
end

local monitorSide = nil
for _, side in ipairs(sides) do
    if peripheral.getType(side) == "monitor" then
        monitorSide = side
        break
    end
end

local mon = peripheral.wrap(monitorSide)
local w, h = mon.getSize()

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
