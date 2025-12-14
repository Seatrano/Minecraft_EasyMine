local logger = require("helper.logger")
local log = logger.new()
local MasterConfig = {}
MasterConfig.__index = MasterConfig

local configName = "masterConfig.txt"

function MasterConfig:new()
    local obj = {
        -- static config
        chunkTimeout = 30000,
        turtleTimeout = 5000,
        firstStartPoint = {x=448, y=74, z=64},
        chestCoordinates = {x=448, y=75, z=64, direction=1},
        maxDepth = -60,

        -- state
        chunks = {},
        turtles = {},
        startPoint = nil,

        trash = { 
            ["minecraft:cobblestone"] = true, 
            ["minecraft:dirt"] = true, 
            ["minecraft:andesite"] = true, 
            ["minecraft:diorite"] = true, 
            ["create:limestone_cobblestone"] = true,
            ["minecraft:gravel"] = true, 
            ["minecraft:granite"] = true, 
            ["minecraft:cobbled_deepslate"] = true 
        }
    }

    obj.startPoint = obj.firstStartPoint
    return setmetatable(obj, MasterConfig)
end

-- Hilfsfunktion: Erstellt eine tiefe Kopie ohne Referenzen
local function deepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = deepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

-- Hilfsfunktion: Bereinigt eine Tabelle für Serialisierung
local function cleanForSerialization(tbl)
    if type(tbl) ~= "table" then
        return tbl
    end
    
    local cleaned = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            cleaned[k] = cleanForSerialization(v)
        else
            cleaned[k] = v
        end
    end
    return cleaned
end

function MasterConfig:save(path)
    -- Erstelle saubere Kopien der State-Daten
    local chunksClean = {}
    for i, chunk in ipairs(self.chunks) do
        chunksClean[i] = {
            chunkNumber = chunk.chunkNumber,
            chunkCoordinates = {
                startX = chunk.chunkCoordinates.startX,
                startZ = chunk.chunkCoordinates.startZ,
                endX = chunk.chunkCoordinates.endX,
                endZ = chunk.chunkCoordinates.endZ
            },
            currentChunkDepth = chunk.currentChunkDepth,
            workedByTurtleName = chunk.workedByTurtleName,
            chunkLastUpdate = chunk.chunkLastUpdate,
            startDirection = chunk.startDirection
        }
    end

    local turtlesClean = {}
    for name, turtle in pairs(self.turtles) do
        turtlesClean[name] = {
            turtleName = turtle.turtleName,
            coordinates = turtle.coordinates and {
                x = turtle.coordinates.x,
                y = turtle.coordinates.y,
                z = turtle.coordinates.z
            } or nil,
            direction = turtle.direction,
            lastUpdate = turtle.lastUpdate,
            status = turtle.status,
            chunkNumber = turtle.chunkNumber,
            fuelLevel = turtle.fuelLevel
        }
    end

    local dataToSave = {
        config = {
            chunkTimeout = self.chunkTimeout,
            turtleTimeout = self.turtleTimeout,
            firstStartPoint = {
                x = self.firstStartPoint.x,
                y = self.firstStartPoint.y,
                z = self.firstStartPoint.z
            },
            chestCoordinates = {
                x = self.chestCoordinates.x,
                y = self.chestCoordinates.y,
                z = self.chestCoordinates.z,
                direction = self.chestCoordinates.direction
            },
            maxDepth = self.maxDepth,
            trash = cleanForSerialization(self.trash)
        },
        state = {
            startPoint = self.startPoint and {
                x = self.startPoint.x,
                y = self.startPoint.y,
                z = self.startPoint.z
            } or nil,
            chunks = chunksClean,
            turtles = turtlesClean
        }
    }

    local file = fs.open(path, "w")
    local success, serialized = pcall(textutils.serialize, dataToSave)
    
    if not success then
        file.close()
        log:logDebug("Master", "ERROR: Failed to serialize config: " .. tostring(serialized))
        error("Failed to serialize config: " .. tostring(serialized))
    end
    
    file.write(serialized)
    file.close()
end

function MasterConfig:load(path)
    if not fs.exists(path) then
        -- echter First Start
        self.startPoint = {x = self.firstStartPoint.x, y = self.firstStartPoint.y, z = self.firstStartPoint.z}
        self.chunks = {}
        self.turtles = {}
        return false
    end

    local file = fs.open(path, "r")
    local content = file.readAll()
    file.close()

    local success, data = pcall(textutils.unserialize, content)
    if not success or not data then 
        log:logDebug("Master", "ERROR: Failed to load config: " .. tostring(data))
        return false 
    end

    local cfg = data.config or {}
    local st  = data.state or {}

    -- Config
    self.chunkTimeout = cfg.chunkTimeout or self.chunkTimeout
    self.turtleTimeout = cfg.turtleTimeout or self.turtleTimeout
    self.firstStartPoint = cfg.firstStartPoint or self.firstStartPoint
    self.chestCoordinates = cfg.chestCoordinates or self.chestCoordinates
    self.maxDepth = cfg.maxDepth or self.maxDepth
    self.trash = cfg.trash or self.trash

    -- State
    self.startPoint = st.startPoint or {x = self.firstStartPoint.x, y = self.firstStartPoint.y, z = self.firstStartPoint.z}
    self.chunks = st.chunks or {}
    self.turtles = st.turtles or {}

    -- Validierung: Stelle sicher, dass alle Chunks korrekt initialisiert sind
    self:validateChunks()

    return true
end

function MasterConfig:validateChunks()
    -- Prüfe und repariere alle Chunks
    for i, chunk in ipairs(self.chunks) do
        if not chunk.chunkNumber then
            chunk.chunkNumber = i
        end
        if not chunk.chunkCoordinates then
            chunk.chunkCoordinates = self:getChunkCoordinates(i)
        end
        if not chunk.currentChunkDepth then
            chunk.currentChunkDepth = self.firstStartPoint.y
        end
        if not chunk.chunkLastUpdate then
            chunk.chunkLastUpdate = 0
        end
        if not chunk.startDirection then
            chunk.startDirection = 2
        end
    end
end

function MasterConfig:isChunkOccupied(chunkNumber, excludeTurtle)
    -- Prüfe, ob irgendeine ANDERE aktive Turtle an diesem Chunk arbeitet
    for name, turtle in pairs(self.turtles) do
        if name ~= excludeTurtle and turtle.chunkNumber == chunkNumber then
            -- Prüfe, ob diese Turtle noch aktiv ist (nicht timed out)
            local lastUpdate = turtle.lastUpdate or 0
            local now = os.epoch("utc")
            if now - lastUpdate < self.turtleTimeout then
                log:logDebug("Master", "Chunk " .. chunkNumber .. " is occupied by active turtle: " .. name)
                return true, name
            end
        end
    end
    return false, nil
end

function MasterConfig:findChunk(turtleName)
    local now = os.epoch("utc")

    -- SCHRITT 1: Hat diese Turtle bereits einen zugewiesenen Chunk?
    if self.turtles[turtleName] and self.turtles[turtleName].chunkNumber then
        local existingChunkNum = self.turtles[turtleName].chunkNumber
        local existingChunk = self.chunks[existingChunkNum]
        
        if existingChunk and existingChunk.currentChunkDepth > self.maxDepth then
            -- Chunk ist noch nicht fertig
            local isOccupied, occupyingTurtle = self:isChunkOccupied(existingChunkNum, turtleName)
            
            if not isOccupied then
                -- Chunk ist frei oder gehört dieser Turtle
                existingChunk.workedByTurtleName = turtleName
                existingChunk.chunkLastUpdate = now
                log:logDebug("Master", "Reassigning existing chunk " .. existingChunkNum .. " to " .. turtleName)
                return existingChunk
            else
                -- Chunk ist von anderer Turtle besetzt - alte Zuweisung ungültig
                log:logDebug("Master", "Turtle " .. turtleName .. "'s old chunk " .. existingChunkNum .. " is now occupied by " .. occupyingTurtle)
                self.turtles[turtleName].chunkNumber = nil
            end
        end
    end

    -- SCHRITT 2: Suche nach einem wirklich freien, unfertigen Chunk
    for i, chunk in ipairs(self.chunks) do
        if chunk.currentChunkDepth > self.maxDepth then
            -- Chunk ist noch nicht fertig - prüfe ob er frei ist
            local isOccupied, occupyingTurtle = self:isChunkOccupied(i, turtleName)
            
            if not isOccupied then
                -- Doppelte Prüfung: Ist workedByTurtleName leer ODER timed out?
                local isFree = true
                if chunk.workedByTurtleName and chunk.workedByTurtleName ~= "" then
                    -- Prüfe ob die zugewiesene Turtle noch aktiv ist
                    if self.turtles[chunk.workedByTurtleName] then
                        local lastUpdate = self.turtles[chunk.workedByTurtleName].lastUpdate or 0
                        if now - lastUpdate < self.turtleTimeout then
                            isFree = false -- Chunk ist noch aktiv belegt
                        end
                    end
                end
                
                if isFree then
                    chunk.workedByTurtleName = turtleName
                    chunk.chunkLastUpdate = now
                    log:logDebug("Master", "Assigning free chunk " .. chunk.chunkNumber .. " to " .. turtleName)
                    return chunk
                else
                    log:logDebug("Master", "Chunk " .. chunk.chunkNumber .. " appears free but is still assigned to " .. chunk.workedByTurtleName)
                end
            end
        end
    end

    -- SCHRITT 3: Keiner frei → neuen Chunk erzeugen
    local newIndex = #self.chunks + 1
    local chunk = self:createChunk(newIndex, turtleName)

    log:logDebug("Master", "Created new chunk " .. chunk.chunkNumber .. " for turtle " .. turtleName)
    return chunk
end

function MasterConfig:getChunkCoordinates(chunkNumber)
    local step = 16
    local x = self.firstStartPoint.x
    local z = self.firstStartPoint.z

    local dir = 1  -- 1=East, 2=South, 3=West, 4=North
    local steps_in_dir = 1
    local steps_done = 0
    local change_after = 2

    if chunkNumber == 1 then
        return {
            startX = x,
            startZ = z,
            endX = x + step - 1,
            endZ = z + step - 1
        }
    end

    -- Spirale im Uhrzeigersinn: East -> South -> West -> North
    for _ = 2, chunkNumber do
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
        endX = x + step - 1,
        endZ = z + step - 1
    }
end

function MasterConfig:createChunk(chunkNumber, turtleName)
    local coords = self:getChunkCoordinates(chunkNumber)
    
    local newChunk = {
        chunkNumber = chunkNumber,
        chunkCoordinates = {
            startX = coords.startX,
            startZ = coords.startZ,
            endX = coords.endX,
            endZ = coords.endZ
        },
        currentChunkDepth = self.firstStartPoint.y,
        workedByTurtleName = turtleName,
        chunkLastUpdate = os.epoch("utc"),
        startDirection = 2  -- East
    }

    self.chunks[chunkNumber] = newChunk
    log:logDebug("Master", "Created chunk " .. chunkNumber .. " at X:" .. coords.startX .. " Z:" .. coords.startZ)
    
    return newChunk
end

function MasterConfig:buildTurtleConfig(turtleName, chunkNumber)
    local chunk = self.chunks[chunkNumber]
    
    if not chunk then
        log:logDebug("Master", "ERROR: Chunk " .. chunkNumber .. " does not exist!")
        return nil
    end

    -- Erstelle eine saubere Kopie der Konfiguration
    return {
        type = "config",
        turtleName = turtleName,
        chunkNumber = chunk.chunkNumber,
        chunkCoordinates = { 
            startX = chunk.chunkCoordinates.startX, 
            startZ = chunk.chunkCoordinates.startZ, 
            endX = chunk.chunkCoordinates.endX, 
            endZ = chunk.chunkCoordinates.endZ 
        },
        chestCoordinates = {
            x = self.chestCoordinates.x,
            y = self.chestCoordinates.y,
            z = self.chestCoordinates.z,
            direction = self.chestCoordinates.direction or 1
        },
        currentChunkDepth = chunk.currentChunkDepth,
        startDirection = chunk.startDirection or 2,
        maxDepth = self.maxDepth,
        trash = cleanForSerialization(self.trash)
    }
end

return MasterConfig