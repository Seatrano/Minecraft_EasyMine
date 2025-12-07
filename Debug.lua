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

mon.setTextScale(1)
mon.clear()

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
