local logger = require("helper.logger")
local log = logger.new()
local MasterConfig = {}
MasterConfig.__index = MasterConfig
local STATE_PATH = "globalData.txt"


function MasterConfig:new()
    local obj = {
        -- static config
        chunkTimeout = 30000,
        turtleTimeout = 5000,
        firstStartPoint = {x=448,y=74,z=64},
        chestCoordinates = {x=448,y=75,z=64},
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

function MasterConfig:saveConfig(path)
    local file = fs.open(path, "w")
    file.write(textutils.serialize({
        version = self.version,
        chunkTimeout = self.chunkTimeout,
        turtleTimeout = self.turtleTimeout,
        firstStartPoint = self.firstStartPoint,
        chestCoordinates = self.chestCoordinates,
        maxDepth = self.maxDepth
    }))
    file.close()
end

function MasterConfig:loadConfig(path)
    if not fs.exists(path) then
        return false
    end

    local file = fs.open(path, "r")
    local data = textutils.unserialize(file.readAll())
    file.close()

    if not data then return false end

    self.chunkTimeout = data.chunkTimeout or self.chunkTimeout
    self.turtleTimeout = data.turtleTimeout or self.turtleTimeout
    self.firstStartPoint = data.firstStartPoint or self.firstStartPoint
    self.chestCoordinates = data.chestCoordinates or self.chestCoordinates
    self.maxDepth = data.maxDepth or self.maxDepth

    self.startPoint = self.firstStartPoint
    return true
end

function MasterConfig:findChunk(turtleName)
    local now = os.epoch("utc")

    -- Defaults setzen
    for i, chunk in ipairs(self.chunks) do
        chunk.workedByTurtleName = chunk.workedByTurtleName or nil
        chunk.chunkLastUpdate = chunk.chunkLastUpdate or 0
        chunk.currentChunkDepth = chunk.currentChunkDepth or self.firstStartPoint.y
        chunk.chunkCoordinates = chunk.chunkCoordinates or self:getChunkCoordinates(i)
        chunk.chunkNumber = chunk.chunkNumber or i
    end

    -- Freien Chunk suchen
    for i, chunk in ipairs(self.chunks) do
        log:logDebug(
            "Master",
            "Checking chunk " .. chunk.chunkNumber ..
            " workedByTurtleName=" .. tostring(chunk.workedByTurtleName) ..
            " currentChunkDepth=" .. tostring(chunk.currentChunkDepth)
        )

        if chunk.currentChunkDepth > self.maxDepth and chunk.workedByTurtleName == nil then
            chunk.workedByTurtleName = turtleName
            chunk.chunkLastUpdate = now
            log:logDebug("Master", "Assigning existing chunk " .. chunk.chunkNumber .. " to " .. turtleName)

            self:saveState(STATE_PATH)
            return chunk
        end
    end

    -- Keiner frei → neuen Chunk erzeugen
    local newIndex = #self.chunks + 1
    local chunk = self:getOrCreateChunk(newIndex, turtleName)

    log:logDebug(
        "Master",
        "No free chunk found. Created new chunk " .. chunk.chunkNumber .. " for turtle " .. turtleName
    )

    self:saveState("globalData.txt")
    return chunk
end



function MasterConfig:getChunkCoordinates(chunkNumber)
    local step = 16
    local x = self.firstStartPoint.x
    local z = self.firstStartPoint.z

    local dir = 1
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

    for _ = 2, chunkNumber do
        if dir == 1 then x = x + step
        elseif dir == 2 then z = z + step
        elseif dir == 3 then x = x - step
        elseif dir == 4 then z = z - step end

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




function MasterConfig:getOrCreateChunk(n, turtleName)
    if self.chunks[n] then
        return self.chunks[n]
    end

    local newChunk = {
        chunkNumber = n,
        chunkCoordinates = self:getChunkCoordinates(n),
        currentChunkDepth = self.firstStartPoint.y,
        workedByTurtleName = turtleName,
        chunkLastUpdate = os.epoch("utc"),
        startDirection = 2
    }

    self.chunks[n] = newChunk
    return newChunk
end


function MasterConfig:saveState(path)
    local file = fs.open(path, "w")
    file.write(textutils.serialize({
        startPoint = self.startPoint,
        chunks = self.chunks,
        turtles = self.turtles
    }))
    file.close()
end

function MasterConfig:loadState(path)
    if not fs.exists(path) then
        self.startPoint = self.firstStartPoint
        self.chunks = {}
        self.turtles = {}
        return false
    end

    local file = fs.open(path, "r")
    local data = textutils.unserialize(file.readAll())
    file.close()

    if not data then return false end

    self.startPoint = data.startPoint or self.firstStartPoint
    self.chunks = data.chunks or {}
    self.turtles = data.turtles or {}

    return true
end


function MasterConfig:buildTurtleConfig(turtleName, chunkNumber)
    local chunk = self.chunks[chunkNumber]

    return {
        type = "config",
        turtleName = turtleName,
        chunkNumber = chunkNumber,
        chunkCoordinates = { 
            startX = chunk.chunkCoordinates.startX, 
            startZ = chunk.chunkCoordinates.startZ, 
            endX = chunk.chunkCoordinates.endX, 
            endZ = chunk.chunkCoordinates.endZ 
        },
        chestCoordinates = self.chestCoordinates,
        currentChunkDepth = chunk.currentChunkDepth,
        startDirection = chunk.startDirection or 1,
        maxDepth = self.maxDepth,
        trash = self.trash
    }
end


return MasterConfig
