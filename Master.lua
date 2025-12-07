local DeviceFinder = require("helper.DeviceFinder")

local version = "3.9.3"
local chunkTimeout = 30 * 1000 -- 30 Sekunden
local turtleTimeout = 5 * 1000 -- 5 Sekunden
local chunkLastCheck = os.epoch("utc")
local turtleLastCheck = os.epoch("utc")
local firstStartPoint = {
    x = 96,
    z = 64,
    y = 254
}

local chestCoordinates = {
    x = 0,
    y = 0,
    z = 0
}

local maxDepth = -60

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
    turtles = {}
}

local function saveGlobalData(localData)
    local file = fs.open("globalData.txt", "w")
    file.write(textutils.serialize(localData))
    file.close()
end

local finder = DeviceFinder.new()

finder:openModem()
local mon = finder:getMonitor()

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

    -- Muss erzeugt werden → Spiral berechnen
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
    for i, chunk in pairs(globalData.chunks) do
        chunk.workedByTurtleName = chunk.workedByTurtleName or nil
        chunk.chunkLastUpdate = chunk.chunkLastUpdate or 0
        chunk.currentChunkDepth = chunk.currentChunkDepth or globalData.startPoint.y
        chunk.chunkCoordinates = chunk.chunkCoordinates or getChunkCoordinates(i)
    end

    -- Freien Chunk suchen
    for i, chunk in pairs(globalData.chunks) do
        if chunk.currentChunkDepth > maxDepth and chunk.workedByTurtleName == nil then
            chunk.workedByTurtleName = turtleName
            chunk.chunkLastUpdate = now
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

local function padRight(str, length)
    str = tostring(str or "?")
    if #str < length then
        return string.rep(" ", length - #str) .. str
    else
        return str
    end
end

local function padLeft(str, length)
    str = tostring(str or "?")
    if #str < length then
        return str .. string.rep(" ", length - #str)
    else
        return str
    end
end

local function fixGlobalData()
    -- globalData.chunks[2].workedByTurtleName = "MT1"
    -- globalData.chunks[1].workedByTurtleName = nil
    -- globalData.chunks[1].currentChunkDepth = 250
    -- globalData.chunks[1].lastUpdate = nil
    -- globalData.chunks[1].chunkCoordinates = {
    --     startX = 96,
    --     startZ = 64,
    --     endX = 112,
    --     endZ = 80
    -- }

    saveGlobalData(globalData)
end

print("Master Computer Version " .. version)
fixGlobalData()

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
        local id, msg = rednet.receive("MT")
        if msg then
            local data = textutils.unserialize(msg)

            if data.type == "newConnection" then
                globalData.turtles[data.turtleName] = {
                    turtleName = data.turtleName,
                    coordinates = data.coordinates,
                    direction = data.direction,
                    lastUpdate = now
                }

                local data = findChunk(data.turtleName)
                data.chestCoordinates = chestCoordinates

                -- Antwort an die Turtle
                rednet.send(id, textutils.serialize(data), data.turtleName)
                saveGlobalData(globalData)
            end

            if data.type == "updateLayer" then
                local chunkNumber = data.chunkNumber
                globalData.chunks[chunkNumber].currentChunkDepth = data.height
                saveGlobalData(globalData)
            end

            if data.type == "update" then
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

            local name = padLeft(t.turtleName, 4)
            local x = padRight(t.coordinates and t.coordinates.x or "?", 4)
            local y = padRight(t.coordinates and t.coordinates.y or "?", 4)
            local z = padRight(t.coordinates and t.coordinates.z or "?", 4)
            local dirStr = padLeft(directionToString(t.direction), 6)
            local fuel = padRight(t.fuelLevel or "?", 5)
            local status = padLeft(t.status or "?", 10)
            local chunk = padRight(t.chunkNumber or "?", 3)

            mon.write(name .. " X:" .. x .. " Z:" .. z .. " Y:" .. y .. " Dir:" .. dirStr .. " Fuel:" .. fuel ..
                          " Chunk:" .. chunk .. " Status:" .. status)

            row = row + 1
        end

    end
end

local function sendDebugInfo()
    local time = os.epoch("utc")

    rednet.broadcast({
        debug = globalData
    }, "Debug")
end

while true do
    parallel.waitForAny(sendMessageToMonitor, sendDebugInfo)
    sleep(1)
end