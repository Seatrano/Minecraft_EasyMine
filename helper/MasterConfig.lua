-- ============================================================================
-- MASTERCONFIG.LUA - Configuration and State Management for Master
-- ============================================================================

local logger = require("helper.logger")
local log = logger.new()

-- ============================================================================
-- MODULE DEFINITION
-- ============================================================================

local MasterConfig = {}
MasterConfig.__index = MasterConfig

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local DEFAULT_CONFIG = {
    chunkTimeout = 30000,
    turtleTimeout = 10000,
    firstStartPoint = {x = 448, y = 74, z = 64},
    chestCoordinates = {x = 448, y = 75, z = 64, direction = 1},
    maxDepth = -60,
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

local CHUNK_SIZE = 16

-- ============================================================================
-- CONSTRUCTOR
-- ============================================================================

function MasterConfig:new()
    local obj = {
        -- Static configuration
        chunkTimeout = DEFAULT_CONFIG.chunkTimeout,
        turtleTimeout = DEFAULT_CONFIG.turtleTimeout,
        firstStartPoint = {
            x = DEFAULT_CONFIG.firstStartPoint.x,
            y = DEFAULT_CONFIG.firstStartPoint.y,
            z = DEFAULT_CONFIG.firstStartPoint.z
        },
        chestCoordinates = {
            x = DEFAULT_CONFIG.chestCoordinates.x,
            y = DEFAULT_CONFIG.chestCoordinates.y,
            z = DEFAULT_CONFIG.chestCoordinates.z,
            direction = DEFAULT_CONFIG.chestCoordinates.direction
        },
        maxDepth = DEFAULT_CONFIG.maxDepth,
        trash = {},
        
        -- Dynamic state
        chunks = {},
        turtles = {},
        startPoint = nil
    }
    
    -- Deep copy trash table
    for item, value in pairs(DEFAULT_CONFIG.trash) do
        obj.trash[item] = value
    end
    
    obj.startPoint = {
        x = obj.firstStartPoint.x,
        y = obj.firstStartPoint.y,
        z = obj.firstStartPoint.z
    }
    
    return setmetatable(obj, MasterConfig)
end

-- ============================================================================
-- SERIALIZATION HELPERS
-- ============================================================================

local Serialization = {}

function Serialization.deepCopy(orig)
    if type(orig) ~= 'table' then
        return orig
    end
    
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = Serialization.deepCopy(v)
    end
    return copy
end

function Serialization.cleanTable(tbl)
    if type(tbl) ~= "table" then
        return tbl
    end
    
    local cleaned = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            cleaned[k] = Serialization.cleanTable(v)
        else
            cleaned[k] = v
        end
    end
    return cleaned
end

function Serialization.prepareChunks(chunks)
    local cleaned = {}
    
    for i, chunk in ipairs(chunks) do
        cleaned[i] = {
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
    
    return cleaned
end

function Serialization.prepareTurtles(turtles)
    local cleaned = {}
    
    for name, turtle in pairs(turtles) do
        cleaned[name] = {
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
    
    return cleaned
end

-- ============================================================================
-- FILE OPERATIONS
-- ============================================================================

function MasterConfig:save(path)
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
            trash = Serialization.cleanTable(self.trash)
        },
        state = {
            startPoint = self.startPoint and {
                x = self.startPoint.x,
                y = self.startPoint.y,
                z = self.startPoint.z
            } or nil,
            chunks = Serialization.prepareChunks(self.chunks),
            turtles = Serialization.prepareTurtles(self.turtles)
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
        -- First start - initialize with defaults
        self.startPoint = {
            x = self.firstStartPoint.x,
            y = self.firstStartPoint.y,
            z = self.firstStartPoint.z
        }
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
    local st = data.state or {}
    
    -- Load configuration
    self.chunkTimeout = cfg.chunkTimeout or self.chunkTimeout
    self.turtleTimeout = cfg.turtleTimeout or self.turtleTimeout
    self.firstStartPoint = cfg.firstStartPoint or self.firstStartPoint
    self.chestCoordinates = cfg.chestCoordinates or self.chestCoordinates
    self.maxDepth = cfg.maxDepth or self.maxDepth
    self.trash = cfg.trash or self.trash
    
    -- Load state
    self.startPoint = st.startPoint or {
        x = self.firstStartPoint.x,
        y = self.firstStartPoint.y,
        z = self.firstStartPoint.z
    }
    self.chunks = st.chunks or {}
    self.turtles = st.turtles or {}
    
    -- Validate and repair data
    self:validateChunks()
    
    return true
end

-- ============================================================================
-- VALIDATION
-- ============================================================================

function MasterConfig:validateChunks()
    -- Ensure all chunks have required fields
    for i, chunk in ipairs(self.chunks) do
        if not chunk.chunkNumber then
            chunk.chunkNumber = i
        end
        if not chunk.chunkCoordinates then
            chunk.chunkCoordinates = self:calculateChunkCoordinates(i)
        end
        if not chunk.currentChunkDepth then
            chunk.currentChunkDepth = self.firstStartPoint.y
        end
        if not chunk.chunkLastUpdate then
            chunk.chunkLastUpdate = 0
        end
        if not chunk.startDirection then
            chunk.startDirection = 2 -- East
        end
    end
    
    -- Check for duplicate chunk assignments
    self:checkForDuplicateAssignments()
end

function MasterConfig:checkForDuplicateAssignments()
    local chunkAssignments = {}
    
    -- Collect all assignments
    for turtleName, turtle in pairs(self.turtles) do
        if turtle.chunkNumber then
            if not chunkAssignments[turtle.chunkNumber] then
                chunkAssignments[turtle.chunkNumber] = {}
            end
            table.insert(chunkAssignments[turtle.chunkNumber], turtleName)
        end
    end
    
    -- Fix duplicates
    for chunkNum, turtles in pairs(chunkAssignments) do
        if #turtles > 1 then
            log:logDebug("Master", "WARNING: Chunk " .. chunkNum .. " assigned to multiple turtles")
            
            for _, tName in ipairs(turtles) do
                log:logDebug("Master", "  - " .. tName)
            end
            
            -- Keep only first assignment
            for i = 2, #turtles do
                local tName = turtles[i]
                log:logDebug("Master", "Removing chunk " .. chunkNum .. " from " .. tName)
                self.turtles[tName].chunkNumber = nil
                self.turtles[tName].status = "needs_reassignment"
            end
            
            -- Update chunk status
            if self.chunks[chunkNum] then
                self.chunks[chunkNum].workedByTurtleName = turtles[1]
            end
        end
    end
end

-- ============================================================================
-- CHUNK MANAGEMENT
-- ============================================================================

local ChunkManager = {}

function ChunkManager.calculateSpiral(chunkNumber, startX, startZ, step)
    if chunkNumber == 1 then
        return startX, startZ
    end
    
    local x, z = startX, startZ
    local dir = 1 -- 1=East, 2=South, 3=West, 4=North
    local stepsInDir = 1
    local stepsDone = 0
    local changeAfter = 2
    
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
        
        stepsDone = stepsDone + 1
        if stepsDone == stepsInDir then
            dir = dir % 4 + 1
            stepsDone = 0
            changeAfter = changeAfter - 1
            if changeAfter == 0 then
                stepsInDir = stepsInDir + 1
                changeAfter = 2
            end
        end
    end
    
    return x, z
end

function MasterConfig:calculateChunkCoordinates(chunkNumber)
    local x, z = ChunkManager.calculateSpiral(
        chunkNumber,
        self.firstStartPoint.x,
        self.firstStartPoint.z,
        CHUNK_SIZE
    )
    
    return {
        startX = x,
        startZ = z,
        endX = x + CHUNK_SIZE - 1,
        endZ = z + CHUNK_SIZE - 1
    }
end

function MasterConfig:createChunk(chunkNumber, turtleName)
    local coords = self:calculateChunkCoordinates(chunkNumber)
    
    local newChunk = {
        chunkNumber = chunkNumber,
        chunkCoordinates = coords,
        currentChunkDepth = self.firstStartPoint.y,
        workedByTurtleName = turtleName,
        chunkLastUpdate = os.epoch("utc"),
        startDirection = 2 -- East
    }
    
    self.chunks[chunkNumber] = newChunk
    log:logDebug("Master", "Created chunk " .. chunkNumber .. " at X:" .. coords.startX .. " Z:" .. coords.startZ)
    
    return newChunk
end

function MasterConfig:findChunk(turtleName)
    local now = os.epoch("utc")
    
    log:logDebug("Master", "Finding chunk for " .. turtleName)
    
    -- Find free unfinished chunk
    for i, chunk in ipairs(self.chunks) do
        local isFree = (chunk.workedByTurtleName == nil or chunk.workedByTurtleName == "")
        local isUnfinished = chunk.currentChunkDepth > self.maxDepth
        
        if isUnfinished and isFree then
            chunk.workedByTurtleName = turtleName
            chunk.chunkLastUpdate = now
            log:logDebug("Master", "Assigning free chunk " .. chunk.chunkNumber .. " to " .. turtleName)
            return chunk
        end
    end
    
    -- No free chunk - create new one
    local newIndex = #self.chunks + 1
    local chunk = self:createChunk(newIndex, turtleName)
    
    log:logDebug("Master", "Created new chunk " .. chunk.chunkNumber .. " for " .. turtleName)
    return chunk
end

-- ============================================================================
-- CONFIGURATION BUILDING
-- ============================================================================

function MasterConfig:buildTurtleConfig(turtleName, chunkNumber)
    local chunk = self.chunks[chunkNumber]
    
    if not chunk then
        log:logDebug("Master", "ERROR: Chunk " .. chunkNumber .. " does not exist")
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
        trash = Serialization.cleanTable(self.trash)
    }
end

-- ============================================================================
-- MODULE EXPORT
-- ============================================================================

return MasterConfig