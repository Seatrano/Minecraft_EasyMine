-- ============================================================================
-- MASTER.LUA - Central Coordinator for Mining Turtles
-- ============================================================================

local DeviceFinder = require("helper.getDevices")
local monitorFunctions = require("helper.monitorFunctions")
local logger = require("helper.logger")
local MasterConfig = require("helper.MasterConfig")

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local finder = DeviceFinder.new()
local monitor = monitorFunctions.new()
local log = logger.new()
local masterConfig = MasterConfig:new()

finder:openModem()

local CONFIG_FILE = "masterConfig.txt"

-- ============================================================================
-- STATE MANAGEMENT
-- ============================================================================

local State = {
    -- Identity
    computerId = os.getComputerID(),
    
    -- Locking mechanism for chunk assignment
    assignmentLock = false,
    assignmentQueue = {},
    reservedNames = {}, -- Track names being assigned to prevent duplicates
    
    -- Timing
    chunkLastCheck = os.epoch("utc"),
    turtleLastCheck = os.epoch("utc"),
    
    -- Monitor
    mon = nil,
    monitorWidth = 0,
    monitorHeight = 0
}

-- ============================================================================
-- INITIALIZATION - Config & Monitor
-- ============================================================================

local function initializeConfig()
    if not masterConfig:load(CONFIG_FILE) then
        log:logDebug("Master", "First start - creating initial config")
        masterConfig:save(CONFIG_FILE)
    end
end

local function initializeMonitor()
    State.mon = finder:getMonitor()
    if State.mon then
        State.monitorWidth, State.monitorHeight = State.mon.getSize()
        State.mon.clear()
        State.mon.setCursorPos(1, 1)
        State.mon.write("Waiting for data...")
    end
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local Utils = {}

function Utils.directionToString(dir)
    local directions = {"North", "East", "South", "West"}
    return directions[dir] or "?"
end

function Utils.extractTurtleNumber(name)
    return tonumber(name:match("%d+")) or 0
end

function Utils.sortTurtlesByNumber(turtles)
    local sorted = {}
    for _, t in pairs(turtles) do
        table.insert(sorted, t)
    end
    
    table.sort(sorted, function(a, b)
        return Utils.extractTurtleNumber(a.turtleName) < Utils.extractTurtleNumber(b.turtleName)
    end)
    
    return sorted
end

-- ============================================================================
-- NAME MANAGEMENT
-- ============================================================================

local NameManager = {}

function NameManager.generateNewName()
    local maxNumber = 0
    
    -- Check existing turtles
    for name, _ in pairs(masterConfig.turtles) do
        local number = Utils.extractTurtleNumber(name)
        if number > maxNumber then
            maxNumber = number
        end
    end
    
    -- Check reserved names
    for name, _ in pairs(State.reservedNames) do
        local number = Utils.extractTurtleNumber(name)
        if number > maxNumber then
            maxNumber = number
        end
    end
    
    local newName = "MT" .. (maxNumber + 1)
    
    -- Reserve immediately
    State.reservedNames[newName] = true
    
    log:logDebug("Master", "Generated new turtle name: " .. newName .. " (reserved)")
    print("Assigning new turtle name: " .. newName)
    
    return newName
end

function NameManager.reserveName(name)
    State.reservedNames[name] = true
end

function NameManager.confirmName(name)
    State.reservedNames[name] = nil
end

function NameManager.getReservedCount()
    local count = 0
    for _ in pairs(State.reservedNames) do
        count = count + 1
    end
    return count
end

-- ============================================================================
-- COMMUNICATION
-- ============================================================================

local Communication = {}

function Communication.sendConfig(turtleId, turtleName, chunkNumber)
    local payload = masterConfig:buildTurtleConfig(turtleName, chunkNumber)
    rednet.send(turtleId, textutils.serialize(payload), "C")
    log:logDebug("Master", "Sent config to " .. turtleName .. " for chunk " .. chunkNumber)
end

-- ============================================================================
-- CONNECTION HANDLING
-- ============================================================================

local ConnectionHandler = {}

function ConnectionHandler.handleReconnection(id, message, now)
    local turtleName = message.turtleName
    
    log:logDebug("Master", "Processing reconnection for: " .. turtleName)
    
    local turtle = masterConfig.turtles[turtleName]
    if not turtle then
        log:logDebug("Master", "Unknown turtle reconnecting, treating as new")
        return ConnectionHandler.handleNewConnection(id, message, now)
    end
    
    -- Update position
    turtle.coordinates = {
        x = message.coordinates.x,
        y = message.coordinates.y,
        z = message.coordinates.z
    }
    turtle.direction = message.direction
    turtle.lastUpdate = now
    turtle.status = "reconnecting"
    
    -- Assign new chunk if needed
    if not turtle.chunkNumber or turtle.chunkNumber == 0 then
        log:logDebug("Master", "Reconnecting turtle needs new chunk")
        local chunk = masterConfig:findChunk(turtleName)
        turtle.chunkNumber = chunk.chunkNumber
    end
    
    -- Send configuration
    Communication.sendConfig(id, turtleName, turtle.chunkNumber)
    masterConfig:save(CONFIG_FILE)
end

function ConnectionHandler.handleNewConnection(id, message, now)
    local turtleName = message.turtleName
    
    -- Check if this is actually a known turtle reconnecting (even if reconnect=false)
    if turtleName and masterConfig.turtles[turtleName] then
        log:logDebug("Master", "Known turtle " .. turtleName .. " connecting (treating as reconnect)")
        return ConnectionHandler.handleReconnection(id, message, now)
    end
    
    -- Generate or reserve name
    if not turtleName or turtleName == "" then
        turtleName = NameManager.generateNewName()
    else
        NameManager.reserveName(turtleName)
    end
    
    log:logDebug("Master", "Processing new connection for: " .. turtleName)
    
    -- LOCK ASSIGNMENT
    State.assignmentLock = true
    
    -- Initialize or reactivate turtle
    if not masterConfig.turtles[turtleName] then
        masterConfig.turtles[turtleName] = {}
    else
        -- Release old chunk if exists
        local oldChunkNum = masterConfig.turtles[turtleName].chunkNumber
        if oldChunkNum and masterConfig.chunks[oldChunkNum] then
            log:logDebug("Master", "Releasing old chunk " .. oldChunkNum)
            masterConfig.chunks[oldChunkNum].workedByTurtleName = nil
            masterConfig.chunks[oldChunkNum].chunkLastUpdate = 0
        end
    end
    
    -- Update turtle data
    masterConfig.turtles[turtleName].turtleName = turtleName
    masterConfig.turtles[turtleName].coordinates = {
        x = message.coordinates.x,
        y = message.coordinates.y,
        z = message.coordinates.z
    }
    masterConfig.turtles[turtleName].direction = message.direction
    masterConfig.turtles[turtleName].lastUpdate = now
    masterConfig.turtles[turtleName].status = "connecting"
    
    -- Assign chunk (CRITICAL SECTION)
    local chunk = masterConfig:findChunk(turtleName)
    masterConfig.turtles[turtleName].chunkNumber = chunk.chunkNumber
    
    -- Save immediately to prevent race conditions
    masterConfig:save(CONFIG_FILE)
    
    log:logDebug("Master", "Assigned chunk " .. chunk.chunkNumber .. " to " .. turtleName)
    
    -- Send configuration
    Communication.sendConfig(id, turtleName, chunk.chunkNumber)
    
    -- Confirm name reservation
    NameManager.confirmName(turtleName)
    
    -- UNLOCK ASSIGNMENT
    State.assignmentLock = false
    log:logDebug("Master", "Released assignment lock for " .. turtleName)
end

function ConnectionHandler.processQueue()
    if State.assignmentLock or #State.assignmentQueue == 0 then
        return
    end
    
    local next = table.remove(State.assignmentQueue, 1)
    if next then
        log:logDebug("Master", "Processing queued connection for " .. (next.message.turtleName or "unknown"))
        
        if next.message.reconnect and next.message.turtleName then
            ConnectionHandler.handleReconnection(next.id, next.message, next.now)
        else
            ConnectionHandler.handleNewConnection(next.id, next.message, next.now)
        end
    end
end

-- ============================================================================
-- MESSAGE HANDLING
-- ============================================================================

local MessageHandler = {}

function MessageHandler.handleChunkRelease(message, now)
    local turtleName = message.turtleName
    local chunkNumber = message.chunkNumber
    
    if not turtleName or not chunkNumber then
        log:logDebug("Master", "Invalid chunk release message")
        return
    end
    
    log:logDebug("Master", "Turtle " .. turtleName .. " releasing chunk " .. chunkNumber)
    
    -- Release the chunk
    if masterConfig.chunks[chunkNumber] then
        if masterConfig.chunks[chunkNumber].workedByTurtleName == turtleName then
            masterConfig.chunks[chunkNumber].workedByTurtleName = nil
            masterConfig.chunks[chunkNumber].chunkLastUpdate = 0
            log:logDebug("Master", "Chunk " .. chunkNumber .. " released successfully")
        else
            log:logDebug("Master", "WARNING: Chunk " .. chunkNumber .. " not owned by " .. turtleName)
        end
    end
    
    -- Update turtle state
    if masterConfig.turtles[turtleName] then
        masterConfig.turtles[turtleName].chunkNumber = 0
        masterConfig.turtles[turtleName].status = "released_chunk"
        masterConfig.turtles[turtleName].lastUpdate = now
    end
    
    masterConfig:save(CONFIG_FILE)
end

function MessageHandler.handleNewConnection(id, message, now)
    log:logDebug("Master", "Received newConnection from ID " .. id)
    
    if State.assignmentLock then
        log:logDebug("Master", "Assignment locked - queuing connection")
        table.insert(State.assignmentQueue, {
            id = id,
            message = message,
            now = now
        })
    else
        if message.reconnect and message.turtleName then
            ConnectionHandler.handleReconnection(id, message, now)
        else
            ConnectionHandler.handleNewConnection(id, message, now)
        end
    end
end

function MessageHandler.handleUpdate(message, now)
    local tName = message.turtleName
    
    if not masterConfig.turtles[tName] then
        -- Unknown turtle - treat as reconnection
        log:logDebug("Master", "Unknown turtle " .. tName .. " - treating as reconnection")
        message.reconnect = true
        
        if State.assignmentLock then
            table.insert(State.assignmentQueue, {
                id = nil,
                message = message,
                now = now
            })
        else
            ConnectionHandler.handleReconnection(nil, message, now)
        end
        return
    end
    
    -- Update known turtle
    masterConfig.turtles[tName].coordinates = {
        x = message.coordinates.x,
        y = message.coordinates.y,
        z = message.coordinates.z
    }
    masterConfig.turtles[tName].direction = message.direction
    masterConfig.turtles[tName].fuelLevel = message.fuelLevel
    masterConfig.turtles[tName].status = message.status
    masterConfig.turtles[tName].lastUpdate = now
    
    -- Update chunk number if changed
    if message.chunkNumber and masterConfig.turtles[tName].chunkNumber ~= message.chunkNumber then
        masterConfig.turtles[tName].chunkNumber = message.chunkNumber
    end
    
    -- Update chunk last update time
    local chunkNum = masterConfig.turtles[tName].chunkNumber
    if chunkNum and masterConfig.chunks[chunkNum] then
        masterConfig.chunks[chunkNum].chunkLastUpdate = now
    end
    
    masterConfig:save(CONFIG_FILE)
end

function MessageHandler.handleLayerUpdate(message, now)
    local tName = message.turtleName
    local height = message.height
    local chunkNum = message.chunkNumber
    
    if masterConfig.turtles[tName] and masterConfig.chunks[chunkNum] then
        masterConfig.chunks[chunkNum].currentChunkDepth = height
        masterConfig.chunks[chunkNum].chunkLastUpdate = now
        
        log:logDebug("Master", "Updated chunk " .. chunkNum .. " depth to " .. height)
        masterConfig:save(CONFIG_FILE)
    else
        log:logDebug("Master", "Received updateLayer from unknown turtle/chunk: " .. tName)
    end
end

-- ============================================================================
-- TIMEOUT MANAGEMENT
-- ============================================================================

local TimeoutManager = {}

function TimeoutManager.checkChunks(now)
    if now - State.chunkLastCheck < masterConfig.chunkTimeout then
        return
    end
    
    State.chunkLastCheck = now
    
    for _, chunk in ipairs(masterConfig.chunks) do
        if chunk.chunkLastUpdate and chunk.chunkLastUpdate > 0 then
            if (now - chunk.chunkLastUpdate) > masterConfig.chunkTimeout then
                log:logDebug("Master", "Chunk " .. chunk.chunkNumber .. " timed out")
                
                -- Set turtle offline
                if chunk.workedByTurtleName and masterConfig.turtles[chunk.workedByTurtleName] then
                    masterConfig.turtles[chunk.workedByTurtleName].status = "offline"
                end
                
                chunk.workedByTurtleName = nil
                chunk.chunkLastUpdate = 0
                masterConfig:save(CONFIG_FILE)
            end
        end
    end
end

function TimeoutManager.checkTurtles(now)
    if now - State.turtleLastCheck < masterConfig.turtleTimeout then
        return
    end
    
    State.turtleLastCheck = now
    
    for name, turtle in pairs(masterConfig.turtles) do
        local last = turtle.lastUpdate or 0
        if now - last > masterConfig.turtleTimeout then
            masterConfig.turtles[name].status = "offline"
        end
    end
    
    masterConfig:save(CONFIG_FILE)
end

-- ============================================================================
-- MONITOR DISPLAY
-- ============================================================================

local MonitorDisplay = {}

function MonitorDisplay.showLockStatus()
    if not State.mon then return 1 end
    
    if State.assignmentLock or #State.assignmentQueue > 0 or NameManager.getReservedCount() > 0 then
        State.mon.setCursorPos(1, 1)
        State.mon.setTextColour(colors.yellow)
        
        local lockText = "LOCK: " .. (State.assignmentLock and "ACTIVE" or "FREE")
        local queueText = " | Queue: " .. #State.assignmentQueue
        local reservedText = " | Reserved: " .. NameManager.getReservedCount()
        
        State.mon.write(lockText .. queueText .. reservedText)
        State.mon.setTextColour(colors.white)
        return 2
    end
    
    return 1
end

function MonitorDisplay.showTurtle(turtle, row)
    if not State.mon or row > State.monitorHeight then
        return false
    end
    
    State.mon.setCursorPos(1, row)
    State.mon.setTextColour(turtle.status == "offline" and colors.red or colors.white)
    
    local name = monitor.padLeft(turtle.turtleName, 4)
    local x = monitor.padRight(turtle.coordinates and turtle.coordinates.x or "?", 4)
    local y = monitor.padRight(turtle.coordinates and turtle.coordinates.y or "?", 4)
    local z = monitor.padRight(turtle.coordinates and turtle.coordinates.z or "?", 4)
    local dirStr = monitor.padLeft(Utils.directionToString(turtle.direction), 6)
    local fuel = monitor.padRight(turtle.fuelLevel or "?", 5)
    local status = monitor.padLeft(turtle.status or "?", 12)
    local chunk = monitor.padRight(turtle.chunkNumber or "?", 3)
    
    State.mon.write(name .. " X:" .. x .. " Z:" .. z .. " Y:" .. y .. 
                   " Dir:" .. dirStr .. " Fuel:" .. fuel ..
                   " Chunk:" .. chunk .. " Status:" .. status)
    
    return true
end

function MonitorDisplay.update()
    if not State.mon then return end
    
    State.mon.clear()
    
    local row = MonitorDisplay.showLockStatus()
    
    local sortedTurtles = Utils.sortTurtlesByNumber(masterConfig.turtles)
    
    for _, turtle in ipairs(sortedTurtles) do
        if not MonitorDisplay.showTurtle(turtle, row) then
            break
        end
        row = row + 1
    end
end

-- ============================================================================
-- MAIN LOOPS
-- ============================================================================

local function mainLoop()
    while true do
        local now = os.epoch("utc")
        
        -- Check for timeouts
        TimeoutManager.checkChunks(now)
        TimeoutManager.checkTurtles(now)
        
        -- Receive messages
        local id, msg = rednet.receive("MT", 0.1)
        if msg and id ~= State.computerId then
            local success, message = pcall(textutils.unserialize, msg)
            
            if success then
                if message.type == "releaseChunk" then
                    MessageHandler.handleChunkRelease(message, now)
                    
                elseif message.type == "newConnection" then
                    MessageHandler.handleNewConnection(id, message, now)
                    
                elseif message.type == "update" and message.turtleName then
                    MessageHandler.handleUpdate(message, now)
                    
                elseif message.type == "updateLayer" and message.turtleName then
                    MessageHandler.handleLayerUpdate(message, now)
                end
            else
                log:logDebug("Master", "Failed to deserialize message from ID " .. id)
            end
        end
        
        -- Process queued connections
        ConnectionHandler.processQueue()
        
        -- Update monitor display
        MonitorDisplay.update()
    end
end

local function debugLoop()
    while true do
        sleep(100)
    end
end

-- ============================================================================
-- MAIN PROGRAM
-- ============================================================================

initializeConfig()
initializeMonitor()

log:logDebug("Master", "Master started, ID: " .. State.computerId)

parallel.waitForAll(mainLoop, debugLoop)