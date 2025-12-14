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

function MasterConfig:save(path)
    local file = fs.open(path, "w")
    file.write(textutils.serialize({
        config = {
            chunkTimeout = self.chunkTimeout,
            turtleTimeout = self.turtleTimeout,
            firstStartPoint = self.firstStartPoint,
            chestCoordinates = self.chestCoordinates,
            maxDepth = self.maxDepth,
            trash = self.trash
        },
        state = {
            startPoint = self.startPoint,
            chunks = self.chunks,
            turtles = self.turtles
        }
    }))
    file.close()
end

function MasterConfig:load(path)
    if not fs.exists(path) then
        -- echter First Start
        self.startPoint = self.firstStartPoint
        self.chunks = {}
        self.turtles = {}
        return false
    end

    local file = fs.open(path, "r")
    local data = textutils.unserialize(file.readAll())
    file.close()

    if not data then return false end

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
    self.startPoint = st.startPoint or self.firstStartPoint
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

function MasterConfig:findChunk(turtleName)
    local now = os.epoch("utc")

    -- Prüfe zuerst, ob die Turtle bereits einen Chunk hat
    if self.turtles[turtleName] and self.turtles[turtleName].chunkNumber then
        local existingChunkNum = self.turtles[turtleName].chunkNumber
        local existingChunk = self.chunks[existingChunkNum]
        
        if existingChunk and existingChunk.currentChunkDepth > self.maxDepth then
            -- Chunk ist noch nicht fertig und kann weiterbearbeitet werden
            if existingChunk.workedByTurtleName == turtleName or existingChunk.workedByTurtleName == nil then
                existingChunk.workedByTurtleName = turtleName
                existingChunk.chunkLastUpdate = now
                log:logDebug("Master", "Reassigning existing chunk " .. existingChunkNum .. " to " .. turtleName)
                return existingChunk
            end
        end
    end

    -- Suche nach einem freien, unfertigen Chunk
    for i, chunk in ipairs(self.chunks) do
        if chunk.currentChunkDepth > self.maxDepth and (chunk.workedByTurtleName == nil or chunk.workedByTurtleName == "") then
            chunk.workedByTurtleName = turtleName
            chunk.chunkLastUpdate = now
            log:logDebug("Master", "Assigning free chunk " .. chunk.chunkNumber .. " to " .. turtleName)
            return chunk
        end
    end

    -- Keiner frei → neuen Chunk erzeugen
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
    local newChunk = {
        chunkNumber = chunkNumber,
        chunkCoordinates = self:getChunkCoordinates(chunkNumber),
        currentChunkDepth = self.firstStartPoint.y,
        workedByTurtleName = turtleName,
        chunkLastUpdate = os.epoch("utc"),
        startDirection = 2  -- East
    }

    self.chunks[chunkNumber] = newChunk
    log:logDebug("Master", "Created chunk " .. chunkNumber .. " at X:" .. newChunk.chunkCoordinates.startX .. " Z:" .. newChunk.chunkCoordinates.startZ)
    
    return newChunk
end

function MasterConfig:buildTurtleConfig(turtleName, chunkNumber)
    local chunk = self.chunks[chunkNumber]
    
    if not chunk then
        log:logDebug("Master", "ERROR: Chunk " .. chunkNumber .. " does not exist!")
        return nil
    end

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
        trash = self.trash
    }
end

return MasterConfig