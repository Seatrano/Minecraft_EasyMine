local DeviceFinder = require("helper.getDevices")
local finder = DeviceFinder.new()
local monitorFunctions = require("helper.monitorFunctions")
local monitor = monitorFunctions.new()
local logger = require("helper.logger")
local log = logger.new()
finder:openModem()

local function getNumber(prompt)
    write(prompt)
    return tonumber(read())
end

local configPath = "/config/config.lua"

local defaultConfig = {
    chunkTimeout = 30 * 1000,
    turtleTimeout = 5 * 1000,

    firstStartPoint = {
        x = 0,
        y = 0,
        z = 0
    },

    chestCoordinates = {
        x = 0,
        y = 0,
        z = 0
    },

    maxDepth = -60
}



-- Ordner sicherstellen
if not fs.exists("/config") then
    fs.makeDir("/config")
end

-- Config erzeugen, wenn nicht vorhanden
if not fs.exists(configPath) then
    print("Enter the start Coordinates of the chunk generation:")
    local coords = {
        x = getNumber("X: "),
        y = getNumber("Y: "),
        z = getNumber("Z: ")
    }

    print("Enter the chest Coordinates for the turtles:")
    local chestCoords = {
        x = getNumber("X: "),
        y = getNumber("Y: "),
        z = getNumber("Z: ")
    }

    local chunkTimeout = getNumber("Enter chunk timeout in seconds (default 30): ") or 30
    local turtleTimeout = getNumber("Enter turtle timeout in seconds (default 5): ") or 5
    defaultConfig.chunkTimeout = chunkTimeout * 1000
    defaultConfig.turtleTimeout = turtleTimeout * 1000

    defaultConfig.firstStartPoint = coords
    defaultConfig.chestCoordinates = chestCoords

    defaultConfig.maxDepth = -60

    local f = fs.open(configPath, "w")
    f.write(textutils.serialize(defaultConfig))
    f.close()
end

-- Config laden
local configFile = fs.open(configPath, "r")
local configContent = configFile.readAll()
configFile.close()
local config = textutils.unserialize(configContent)

-- Werte verwenden
local chunkTimeout = config.chunkTimeout
local turtleTimeout = config.turtleTimeout
local firstStartPoint = config.firstStartPoint
local chestCoordinates = config.chestCoordinates

local chunkLastCheck = os.epoch("utc")
local turtleLastCheck = os.epoch("utc")

local function loadGlobalData()
    if fs.exists("globalData.txt") then
        local file = fs.open("globalData.txt", "r")
        local content = file.readAll()
        file.close()
        return textutils.unserialize(content)
    else
        return nil
    end
end

local globalData = loadGlobalData() or {
    startPoint = firstStartPoint,
    chunks = {},
    turtles = {},
    maxDepth = config.maxDepth
}

local function saveGlobalData(localData)
    local file = fs.open("globalData.txt", "w")
    file.write(textutils.serialize(localData))
    file.close()
end

local mon = finder:getMonitor()
local w, h = mon.getSize()

mon.clear()
mon.setCursorPos(1, 1)
mon.write("Warte auf Daten...")

-- Gibt die Koordinaten des Chunks x zurück
local function getChunkCoordinates(chunkNumber)
    local step = 16
    local x, z = firstStartPoint.x, firstStartPoint.z
    local dir = 1 -- 1=right, 2=up, 3=left, 4=down    
    local steps_in_dir = 1
    local steps_done = 0
    local change_after = 2

    if chunkNumber == 1 then
        return {
            startX = x,
            startZ = z,
            endX = x + step,
            endZ = z + step
        }
    end

    for i = 2, chunkNumber do
        if dir == 1 then
            x = x + step
        elseif dir == 2 then
            z = z + step
        elseif dir == 3 then
            x = x - step
        elseif dir == 4 then
            z = z - step
        end

        steps_done = steps_done + 1
        if steps_done == steps_in_dir then
            dir = dir % 4 + 1
            steps_done = 0
            change_after = change_after - 1
            if change_after == 0 then
                steps_in_dir = steps_in_dir + 1
                change_after = 2
            end
        end
    end

    return {
        startX = x,
        startZ = z,
        endX = x + step,
        endZ = z + step
    }
end

local function directionToString(dir)
    if dir == 1 then
        return "North"
    elseif dir == 2 then
        return "East"
    elseif dir == 3 then
        return "South"
    elseif dir == 4 then
        return "West"
    else
        return "?"
    end
end

-- Gibt den Chunk mit Index n zurück (erzeugt ihn bei Bedarf)
local function getOrCreateChunk(n)
    -- Bereits erzeugt?
    if globalData.chunks[n] then
        return globalData.chunks[n]
    end

    -- Muss erzeugt werden → Spirale berechnen
    local coords = getChunkCoordinates(n)

    local newChunk = {
        chunkNumber = n,
        chunkCoordinates = coords,
        currentChunkDepth = globalData.startPoint.y,
        workedByTurtleName = nil,
        chunkLastUpdate = nil
    }

    globalData.chunks[n] = newChunk
    return newChunk
end

local function findChunk(turtleName)
    local now = os.epoch("utc")

    -- Defaults setzen
    for i, chunk in ipairs(globalData.chunks) do
        chunk.workedByTurtleName = chunk.workedByTurtleName or nil
        chunk.chunkLastUpdate = chunk.chunkLastUpdate or 0
        chunk.currentChunkDepth = chunk.currentChunkDepth or globalData.startPoint.y
        chunk.chunkCoordinates = chunk.chunkCoordinates or getChunkCoordinates(i)
    end

    -- Freien Chunk suchen
    for i, chunk in ipairs(globalData.chunks) do
        log:logDebug("Master", "Checking chunk " .. chunk.chunkNumber .. " workedByTurtleName=" ..
                              tostring(chunk.workedByTurtleName) .. " currentChunkDepth=" .. tostring(
            chunk.currentChunkDepth))
            log:logDebug("Master", "Max depth is " .. tostring(globalData.maxDepth))
        if chunk.currentChunkDepth > globalData.maxDepth and chunk.workedByTurtleName == nil then
            chunk.workedByTurtleName = turtleName
            chunk.chunkLastUpdate = now
            chunk.chunkNumber = i
            print("Assigning existing chunk " .. chunk.chunkNumber .. " to " .. turtleName)
            saveGlobalData(globalData)
            print(textutils.serialize(globalData.chunks[i]))
            return chunk
        end
    end

    -- Keiner frei → neuen Chunk erzeugen
    local newIndex = #globalData.chunks + 1
    local chunk = getOrCreateChunk(newIndex)
    chunk.workedByTurtleName = turtleName
    chunk.chunkLastUpdate = now
    print("No free chunk found. Created new chunk " .. chunk.chunkNumber .. " for turtle " .. turtleName)
    saveGlobalData(globalData)
    return chunk
end

local function fixGlobalData()
    saveGlobalData(globalData)
end

fixGlobalData()

local function getNewTurtleName()
    local maxNumber = 0
    for name, _ in pairs(globalData.turtles) do
        local number = tonumber(name:match("%d+")) or 1
        if number > maxNumber then
            maxNumber = number
        end
    end
    return "MT" .. (maxNumber + 1)
end

local function sendMessageToMonitor()

    while true do
        local now = os.epoch("utc")

        -- 1. Prüfe Chunks auf Timeout
        if now - chunkLastCheck >= chunkTimeout then
            chunkLastCheck = now
            for _, chunk in ipairs(globalData.chunks) do
                if chunk.chunkLastUpdate and (now - chunk.chunkLastUpdate) > chunkTimeout then
                    print("Chunk " .. chunk.chunkNumber .. " timed out. Releasing it.")
                    chunk.workedByTurtleName = nil
                    chunk.chunkLastUpdate = nil
                end
            end
        end

        -- 2. Prüfe Turtles auf Timeout
        if now - turtleLastCheck >= turtleTimeout then
            turtleLastCheck = now
            for name, t in pairs(globalData.turtles) do
                local last = t.lastUpdate or 0
                if now - last > turtleTimeout then
                    globalData.turtles[name].status = "offline"
                    saveGlobalData(globalData)
                end
            end
        end

        -- Nachricht von irgendeiner Turtle empfangen
        local id, msg = rednet.receive()
        print(msg)
        if msg then
            local data = textutils.unserialize(msg)
            log:logDebug("Master", "Received message: " .. (textutils.serialize(data) or "<nil>"))
            if data.type == "newConnection" then

                if not (data.turtleName) then
                    data.turtleName = getNewTurtleName()
                end

                globalData.turtles[data.turtleName] = {
                    turtleName = data.turtleName,
                    coordinates = data.coordinates,
                    direction = data.direction,
                    lastUpdate = now
                }

                local data = findChunk(data.turtleName)
                data.chestCoordinates = chestCoordinates
                data.chunkNumber = data.chunkNumber


                -- Antwort an die Turtle
                log:logDebug("Master", "Assigned to chunk " .. data.chunkNumber .. " at X:" .. data.chunkCoordinates.startX .. " Z:" ..
                          data.chunkCoordinates.startZ)
                rednet.send(id, textutils.serialize(data))
                saveGlobalData(globalData)
            end

            if data.type == "updateLayer" then
                local chunkNumber = data.chunkNumber
                globalData.chunks[chunkNumber].currentChunkDepth = data.height
                saveGlobalData(globalData)
            end

            if data.type == "update" and data.turtleName then
                globalData.turtles[data.turtleName] = {
                    turtleName = data.turtleName,
                    coordinates = data.coordinates,
                    direction = data.direction,
                    fuelLevel = data.fuelLevel,
                    status = data.status,
                    chunkNumber = data.chunkNumber,
                    lastUpdate = now
                }
                if globalData.chunks[data.chunkNumber] then
                    globalData.chunks[data.chunkNumber].workedByTurtleName = data.turtleName
                    globalData.chunks[data.chunkNumber].chunkLastUpdate = os.epoch("utc")
                end
                saveGlobalData(globalData)
            end
        end

        -- Hilfsfunktion: Zahl aus Turtle-Name extrahieren
        local function turtleNumber(name)
            return tonumber(name:match("%d+")) or 0
        end

        -- Turtles als Array sammeln
        local turtlesSorted = {}
        for _, t in pairs(globalData.turtles) do
            table.insert(turtlesSorted, t)
        end

        -- Sortieren nach Zahl im Namen
        table.sort(turtlesSorted, function(a, b)
            return turtleNumber(a.turtleName) < turtleNumber(b.turtleName)
        end)

        mon.clear()
        local row = 1
        for _, t in ipairs(turtlesSorted) do
            if row > h then
                break
            end

            mon.setCursorPos(1, row)

            if (t.status == "offline") then
                mon.setTextColour(colors.red)
            else
                mon.setTextColour(colors.white)
            end

            local name = monitor.padLeft(t.turtleName, 4)
            local x = monitor.padRight(t.coordinates and t.coordinates.x or "?", 4)
            local y = monitor.padRight(t.coordinates and t.coordinates.y or "?", 4)
            local z = monitor.padRight(t.coordinates and t.coordinates.z or "?", 4)
            local dirStr = monitor.padLeft(directionToString(t.direction), 6)
            local fuel = monitor.padRight(t.fuelLevel or "?", 5)
            local status = monitor.padLeft(t.status or "?", 10)
            local chunk = monitor.padRight(t.chunkNumber or "?", 3)

            mon.write(name .. " X:" .. x .. " Z:" .. z .. " Y:" .. y .. " Dir:" .. dirStr .. " Fuel:" .. fuel ..
                          " Chunk:" .. chunk .. " Status:" .. status)

            row = row + 1
        end

    end
end

local function sendDebugInfo()
    log:logDebug("Master", "Master is running.")
end

sendMessageToMonitor()
while true do
    parallel.waitForAll(sendMessageToMonitor, sendDebugInfo)
    sleep(1)
end
