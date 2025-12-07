local configFile = "/config/startup_config.txt"

local function ensureDir(path)
    if not fs.exists(path) then fs.makeDir(path) end
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
        selection = "GPSMaster"
    elseif choice == "2" then
        selection = "Master"
    elseif choice == "3" then
        selection = "Slave"
    elseif choice == "Debug" then
        write("Enter custom program ID/name: ")
        selection = read()
    else
        error("Invalid selection.")
    end

    -- speichern
    local f = fs.open(configFile, "w")
    f.write(selection)
    f.close()

    print("Saved as: " .. selection)
end

-- Downloader je nach Auswahl
local function downloadIfMissing(filename, url)
    if not fs.exists(filename) then
        print("Downloading " .. filename .. " ...")
        shell.run("wget", url, filename)
    end
end

-- Programme laden und starten
if selection == "GPSMaster" then
    downloadIfMissing("startup GPSMaster.lua", "https://raw.githubusercontent.com/Seatrano/Minecraft_EasyMine/main/startup%20GPS.lua")
    shell.run("GPSMasterStart.lua")
elseif selection == "Master" then
    downloadIfMissing("MasterStart.lua", "https://raw.githubusercontent.com/Seatrano/Minecraft_EasyMine/main/startup%20Master.lua")
    shell.run("MasterStart.lua")
elseif selection == "Slave" then
    downloadIfMissing("SlaveStart.lua", "https://raw.githubusercontent.com/Seatrano/Minecraft_EasyMine/main/startup%20Slave.lua")
    shell.run("SlaveStart.lua")
elseif selection == "Debug" then
    downloadIfMissing("DebugStart.lua", "https://raw.githubusercontent.com/Seatrano/Minecraft_EasyMine/main/startup%20Debug.lua")
    shell.run("DebugStart.lua")

else
    error("Unknown selection: " .. selection)
end
