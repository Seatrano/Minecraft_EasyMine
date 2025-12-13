local DeviceFinder = require("helper.getDevices")
local finder = DeviceFinder.new()
local monitorFunctions = require("helper.monitorFunctions")
local monitor = monitorFunctions.new()
local logger = require("helper.logger")
local log = logger.new()
local MasterConfig = require("helper.MasterConfig")

local masterConfig = MasterConfig:new()

local configName = "masterConfig.txt"

if not masterConfig:load(configName) then
    log:logDebug("Master", "First start – creating initial config/state")
    masterConfig:save(configName)
end

finder:openModem()

local computerId = os.getComputerID()

local function getNumber(prompt)
    write(prompt)
    return tonumber(read())
end

local chunkLastCheck = os.epoch("utc")
local turtleLastCheck = os.epoch("utc")

local mon = finder:getMonitor()
local w, h = mon.getSize()

mon.clear()
mon.setCursorPos(1, 1)
mon.write("Warte auf Daten...")

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

local function getNewTurtleName()
    local maxNumber = 0
    for name, _ in pairs(masterConfig.turtles) do
        local number = tonumber(name:match("%d+")) or 0
        if number > maxNumber then
            maxNumber = number
        end
    end
    print("Assigning new turtle name MT" .. (maxNumber + 1))
    return "MT" .. (maxNumber + 1)
end

local function sendMessageToMonitor()

    while true do
        local now = os.epoch("utc")

        -- 1. Prüfe Chunks auf Timeout

        if now - chunkLastCheck >= masterConfig.chunkTimeout then
            chunkLastCheck = now
            for _, chunk in ipairs(masterConfig.chunks) do
                if chunk.chunkLastUpdate ~= nil and chunk.chunkLastUpdate > 0 and (now - chunk.chunkLastUpdate) >
                    masterConfig.chunkTimeout then

                    log:logDebug("Master", "Chunk " .. chunk.chunkNumber .. " timed out. Releasing it.")

                    chunk.workedByTurtleName = nil
                    chunk.chunkLastUpdate = 0
                    masterConfig:save(configName)
                end
            end
        end

        -- 2. Prüfe Turtles auf Timeout
        if now - turtleLastCheck >= masterConfig.turtleTimeout then
            turtleLastCheck = now
            for name, t in pairs(masterConfig.turtles) do
                local last = t.lastUpdate or 0
                if now - last > masterConfig.turtleTimeout then
                    masterConfig.turtles[name].status = "offline"
                end
            end
            masterConfig:save(configName)
        end

        local id, msg = rednet.receive("MT")
        if msg and id ~= computerId then
            local message = textutils.unserialize(msg)
            log:logDebug("Master", "Received message: " .. (textutils.serialize(message) or "<nil>"))

            if message.type == "newConnection" then
                local turtleName = message.turtleName or getNewTurtleName()

                -- Turtle registrieren
                masterConfig.turtles[turtleName] = {
                    turtleName = turtleName,
                    coordinates = message.coordinates,
                    direction = message.direction,
                    lastUpdate = now,
                    status = "online"
                }

                -- Chunk zuweisen
                local chunk = masterConfig:findChunk(turtleName)
                masterConfig.turtles[turtleName].chunkNumber = chunk.chunkNumber

                -- Payload für Turtle bauen
                local payload = masterConfig:buildTurtleConfig(turtleName, chunk.chunkNumber)
                rednet.send(id, textutils.serialize(payload), "C")

                masterConfig:save(configName)

            elseif message.type == "update" and message.turtleName ~= nil then
                local tName = message.turtleName
                if masterConfig.turtles[tName] then
                    -- Koordinaten, Richtung, Fuel, Status aktualisieren
                    masterConfig.turtles[tName].coordinates = message.coordinates
                    masterConfig.turtles[tName].direction = message.direction
                    masterConfig.turtles[tName].fuelLevel = message.fuelLevel
                    masterConfig.turtles[tName].status = message.status
                    masterConfig.turtles[tName].chunkNumber = message.chunkNumber
                    masterConfig.turtles[tName].lastUpdate = os.epoch("utc")

                    log:logDebug("Master", "Updated turtle " .. tName .. " at chunk " .. message.chunkNumber)
                    masterConfig:save(configName)
                else
                    log:logDebug("Master", "Received update for unknown turtle: " .. tName)
                end
            end
        end

        -- Hilfsfunktion: Zahl aus Turtle-Name extrahieren
        local function turtleNumber(name)
            return tonumber(name:match("%d+")) or 0
        end

        -- Turtles als Array sammeln
        local turtlesSorted = {}
        for _, t in pairs(masterConfig.turtles) do
            table.insert(turtlesSorted, t)
        end

        -- Sortieren nach Zahl im Namen
        table.sort(turtlesSorted, function(a, b)
            return turtleNumber(a.turtleName) < turtleNumber(b.turtleName)
        end)

        -- Monitor aktualisieren
        mon.clear()
        local row = 1
        for _, t in ipairs(turtlesSorted) do
            if row > h then
                break
            end

            mon.setCursorPos(1, row)

            mon.setTextColour(t.status == "offline" and colors.red or colors.white)

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

local function sendDebugLoop()
    while true do
        -- sendDebugInfo()
        sleep(100)
    end
end

parallel.waitForAll(sendMessageToMonitor, sendDebugLoop)
