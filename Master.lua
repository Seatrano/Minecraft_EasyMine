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

-- LOCK-MECHANISMUS für Chunk-Zuweisung
local assignmentLock = false
local assignmentQueue = {}

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

local function sendConfigToTurtle(id, turtleName, chunkNumber)
    local payload = masterConfig:buildTurtleConfig(turtleName, chunkNumber)
    rednet.send(id, textutils.serialize(payload), "C")
    log:logDebug("Master", "Sent config to " .. turtleName .. " for chunk " .. chunkNumber)
end

-- Verarbeitet eine neue Turtle-Verbindung mit Lock
local function processNewConnection(id, message, now)
    local turtleName = message.turtleName or getNewTurtleName()
    
    log:logDebug("Master", "Processing new connection for " .. turtleName)
    
    -- LOCK SETZEN
    assignmentLock = true
    
    -- Turtle registrieren oder reaktivieren
    if not masterConfig.turtles[turtleName] then
        masterConfig.turtles[turtleName] = {}
    end
    
    masterConfig.turtles[turtleName].turtleName = turtleName
    masterConfig.turtles[turtleName].coordinates = {
        x = message.coordinates.x,
        y = message.coordinates.y,
        z = message.coordinates.z
    }
    masterConfig.turtles[turtleName].direction = message.direction
    masterConfig.turtles[turtleName].lastUpdate = now
    masterConfig.turtles[turtleName].status = "connecting"

    -- Chunk zuweisen (KRITISCHER BEREICH)
    local chunk = masterConfig:findChunk(turtleName)
    masterConfig.turtles[turtleName].chunkNumber = chunk.chunkNumber
    
    -- Sofort speichern um Race Conditions zu vermeiden
    masterConfig:save(configName)
    
    log:logDebug("Master", "Assigned chunk " .. chunk.chunkNumber .. " to " .. turtleName)

    -- Konfiguration senden
    sendConfigToTurtle(id, turtleName, chunk.chunkNumber)

    -- LOCK FREIGEBEN
    assignmentLock = false
    log:logDebug("Master", "Released assignment lock for " .. turtleName)
end

-- Verarbeitet die Queue
local function processAssignmentQueue()
    if assignmentLock or #assignmentQueue == 0 then
        return
    end
    
    local next = table.remove(assignmentQueue, 1)
    if next then
        log:logDebug("Master", "Processing queued connection for " .. (next.message.turtleName or "unknown"))
        processNewConnection(next.id, next.message, next.now)
    end
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

                    -- Turtle auf offline setzen
                    if chunk.workedByTurtleName and masterConfig.turtles[chunk.workedByTurtleName] then
                        masterConfig.turtles[chunk.workedByTurtleName].status = "offline"
                    end

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

        local id, msg = rednet.receive("MT", 0.1)
        if msg and id ~= computerId then
            local success, message = pcall(textutils.unserialize, msg)
            
            if not success then
                log:logDebug("Master", "Failed to deserialize message from ID " .. id)
            else
                log:logDebug("Master", "Received message type: " .. (message.type or "unknown"))

                if message.type == "newConnection" then
                    -- Prüfe ob Lock aktiv ist
                    if assignmentLock then
                        log:logDebug("Master", "Assignment locked - queuing connection request")
                        table.insert(assignmentQueue, {
                            id = id,
                            message = message,
                            now = now
                        })
                    else
                        -- Lock frei - direkt verarbeiten
                        processNewConnection(id, message, now)
                    end

                elseif message.type == "update" and message.turtleName ~= nil then
                    local tName = message.turtleName
                    
                    if not masterConfig.turtles[tName] then
                        -- Unbekannte Turtle - als neue Connection behandeln
                        log:logDebug("Master", "Unknown turtle " .. tName .. " - treating as new connection")
                        
                        masterConfig.turtles[tName] = {
                            turtleName = tName,
                            coordinates = {
                                x = message.coordinates.x,
                                y = message.coordinates.y,
                                z = message.coordinates.z
                            },
                            direction = message.direction,
                            fuelLevel = message.fuelLevel,
                            status = "reconnecting",
                            chunkNumber = message.chunkNumber,
                            lastUpdate = now
                        }
                        
                        -- Chunk prüfen und ggf. neu zuweisen
                        local chunk = masterConfig:findChunk(tName)
                        masterConfig.turtles[tName].chunkNumber = chunk.chunkNumber
                        
                        sendConfigToTurtle(id, tName, chunk.chunkNumber)
                    else
                        -- Bekannte Turtle - Update verarbeiten
                        masterConfig.turtles[tName].coordinates = {
                            x = message.coordinates.x,
                            y = message.coordinates.y,
                            z = message.coordinates.z
                        }
                        masterConfig.turtles[tName].direction = message.direction
                        masterConfig.turtles[tName].fuelLevel = message.fuelLevel
                        masterConfig.turtles[tName].status = message.status
                        masterConfig.turtles[tName].lastUpdate = now
                        
                        -- Chunk-Update
                        if message.chunkNumber and masterConfig.turtles[tName].chunkNumber ~= message.chunkNumber then
                            masterConfig.turtles[tName].chunkNumber = message.chunkNumber
                        end
                        
                        -- Chunk-LastUpdate aktualisieren
                        local chunkNum = masterConfig.turtles[tName].chunkNumber
                        if chunkNum and masterConfig.chunks[chunkNum] then
                            masterConfig.chunks[chunkNum].chunkLastUpdate = now
                        end
                    end
                    
                    masterConfig:save(configName)

                elseif message.type == "updateLayer" and message.turtleName ~= nil then
                    -- NEUER HANDLER für Layer-Updates
                    local tName = message.turtleName
                    local height = message.height
                    local chunkNum = message.chunkNumber
                    
                    if masterConfig.turtles[tName] and masterConfig.chunks[chunkNum] then
                        masterConfig.chunks[chunkNum].currentChunkDepth = height
                        masterConfig.chunks[chunkNum].chunkLastUpdate = now
                        
                        log:logDebug("Master", "Updated chunk " .. chunkNum .. " depth to " .. height)
                        masterConfig:save(configName)
                    else
                        log:logDebug("Master", "Received updateLayer from unknown turtle/chunk: " .. tName)
                    end
                end
            end
        end
        
        -- Verarbeite wartende Turtles aus der Queue
        processAssignmentQueue()

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
        
        -- Zeige Queue-Status und Counter in erster Zeile
        if assignmentLock or #assignmentQueue > 0 then
            mon.setCursorPos(1, row)
            mon.setTextColour(colors.yellow)
            mon.write("LOCK: " .. (assignmentLock and "ACTIVE" or "FREE") .. " | Queue: " .. #assignmentQueue .. " | Next: MT" .. masterConfig.nextTurtleNumber)
            mon.setTextColour(colors.white)
            row = row + 1
        end
        
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
            local status = monitor.padLeft(t.status or "?", 12)
            local chunk = monitor.padRight(t.chunkNumber or "?", 3)

            mon.write(name .. " X:" .. x .. " Z:" .. z .. " Y:" .. y .. " Dir:" .. dirStr .. " Fuel:" .. fuel ..
                          " Chunk:" .. chunk .. " Status:" .. status)

            row = row + 1
        end
    end
end

local function sendDebugLoop()
    while true do
        sleep(100)
    end
end

parallel.waitForAll(sendMessageToMonitor, sendDebugLoop)