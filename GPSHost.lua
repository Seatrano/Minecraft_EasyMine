local DeviceFinder = require("helper.getDevices")
local finder = DeviceFinder.new()
finder:openModem()

if not os.getComputerLabel() then
    print("This computer has no label.")
    write("Enter a label: ")
    local label = read()
    os.setComputerLabel(label)
    print("Label set to: " .. label)
end

local function getNumber(prompt)
    write(prompt)
    return tonumber(read())
end

local coordsFile = "gps_coords.txt"
local coords = nil

if fs.exists(coordsFile) then
    local f = fs.open(coordsFile, "r")
    coords = textutils.unserialize(f.readAll())
    f.close()
    print("Loaded GPS coordinates: X=" .. coords.x .. " Y=" .. coords.y .. " Z=" .. coords.z)
else
    print("Enter the GPS host position for this computer:")
    coords = {
        x = getNumber("X: "),
        y = getNumber("Y: "),
        z = getNumber("Z: ")
    }

    local f = fs.open(coordsFile, "w")
    f.write(textutils.serialize(coords))
    f.close()
    print("Coordinates saved.")
end

parallel.waitForAny(function()
    shell.run("gps", "host", coords.x, coords.y, coords.z)
end, function()
    while true do
        os.pullEvent("timer")
    end
end)
