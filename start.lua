local configFile = "/config/startup_config.txt"

local function ensureDir(path)
    if not fs.exists(path) then
        fs.makeDir(path)
    end
end

ensureDir("/config")

-- Prüfen, ob bereits ein Programm gewählt wurde
local selection = nil
if fs.exists(configFile) then
    local f = fs.open(configFile, "r")
    selection = f.readAll()
    f.close()
end

if not selection or selection == "" then
    print("Select mode for this computer:")
    print("1) GPS Host")
    print("2) Master")
    print("3) Slave")
    print("4) Debug")

    write("Enter number: ")
    local choice = read()

    if choice == "1" then
        selection = "GPSHost"
    elseif choice == "2" then
        selection = "Master"
    elseif choice == "3" then
        selection = "Slave"
    elseif choice == "4" then
        selection = "Debug"
    else
        error("Invalid selection.")
    end

    -- speichern
    local f = fs.open(configFile, "w")
    f.write(selection)
    f.close()

    print("Saved as: " .. selection)
end

local apiBase = "https://api.github.com/repos/Seatrano/Minecraft_EasyMine/contents/"
local token = "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"
local headers = {
    ["User-Agent"] = "CC",
    ["Accept"] = "application/vnd.github.v3.raw",
    ["Authorization"] = "token " .. token
}

local function downloadFile(path)
    local url = apiBase .. path
    local response = http.get(url, headers)

    if not response then
        print("ERROR downloading " .. path)
        return
    end

    local content = response.readAll()
    response.close()

    -- Ensure folder exists
    local folder = fs.getDir(path)
    if not fs.exists(folder) then
        fs.makeDir(folder)
    end

    local f = fs.open(path, "w")
    f.write(content)
    f.close()

    print("Updated: " .. path)
end

local function updateHelpers()
    local url = apiBase .. "helper"
    local response = http.get(url, {
        ["User-Agent"] = "CC"
    })

    if not response then
        print("ERROR: could not list helper folder")
        return
    end

    local files = textutils.unserializeJSON(response.readAll())
    response.close()

    for _, file in ipairs(files) do
        if file.type == "file" then
            downloadFile("helper/" .. file.name)
        end
    end
end

-- Programme laden und starten
if selection == "GPSHost" then
    downloadFile("GPSHost.lua")
    updateHelpers()
    shell.run("GPSHost.lua")

elseif selection == "Master" then
    downloadFile("Master.lua")
    updateHelpers()
    shell.run("Master.lua")

elseif selection == "Slave" then
    downloadFile("Slave.lua")
    updateHelpers()
    shell.run("Slave.lua")
elseif selection == "Debug" then
    downloadFile("Debug.lua")
    updateHelpers()
    shell.run("Debug.lua")
else
    error("Unknown selection: " .. selection)
end
