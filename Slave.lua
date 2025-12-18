-- ============================================================================
-- SLAVE.LUA - Mining Turtle Controller (FIXED VERSION)
-- ============================================================================

local DeviceFinder = require("helper.getDevices")
local logger = require("helper.logger")

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local finder = DeviceFinder.new()
local log = logger.new()
finder:openModem()

-- ============================================================================
-- STATE MANAGEMENT
-- ============================================================================

local State = {
    -- Identity
    computerId = os.getComputerID(),
    turtleName = os.getComputerLabel(),
    
    -- Position & Direction
    x = nil,
    y = nil,
    z = nil,
    direction = 2, -- 1=North, 2=East, 3=South, 4=West
    
    -- Status
    status = "Idle",
    chunkNumber = 0,
    
    -- Configuration
    startCoords = {x = 0, y = 0, z = 0, direction = 1},
    chestCoords = {},
    trash = {},
    
    -- Command System
    currentCommand = nil,
    commandHandled = false,
    restartMining = false
}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local DIRECTION = {
    NORTH = 1,
    EAST = 2,
    SOUTH = 3,
    WEST = 4
}

local MAX_MOVEMENT_ATTEMPTS = 60
local WAIT_FOR_TURTLE_TIMEOUT = 30
local TURTLE_BLOCK_NAME = "computercraft:turtle_advanced"

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local Utils = {}

function Utils.sleep(seconds)
    for i = 1, seconds do
        print("Sleeping... " .. (seconds - i + 1) .. "s remaining")
        os.sleep(1)
    end
end

function Utils.directionToString(dir)
    local names = {"North", "East", "South", "West"}
    return names[dir] or "Unknown"
end

function Utils.updateGPS()
    while true do
        State.x, State.y, State.z = gps.locate(5)
        if State.x then
            return
        end
        log:logDebug(State.turtleName, "GPS not available, retrying...")
        Utils.sleep(1)
    end
end

function Utils.stableGPS()
    while true do
        local x, y, z = gps.locate(1)
        if x and z then
            return x, y, z
        end
        os.sleep(1)
    end
end

function Utils.randomDelay(minSeconds, maxSeconds)
    local delay = minSeconds + math.random() * (maxSeconds - minSeconds)
    os.sleep(delay)
end

-- ============================================================================
-- COMMUNICATION
-- ============================================================================

local Communication = {}

function Communication.sendUpdate()
    local data = {
        type = "update",
        coordinates = {x = State.x, y = State.y, z = State.z},
        fuelLevel = turtle.getFuelLevel(),
        direction = State.direction,
        status = State.status,
        turtleName = State.turtleName,
        chunkNumber = State.chunkNumber
    }
    rednet.broadcast(textutils.serialize(data), "MT")
end

function Communication.sendLayerUpdate(height)
    local data = {
        type = "updateLayer",
        turtleName = State.turtleName,
        height = height,
        chunkNumber = State.chunkNumber
    }
    rednet.broadcast(textutils.serialize(data), "MT")
end

function Communication.releaseChunk()
    if State.chunkNumber and State.chunkNumber > 0 then
        local data = {
            type = "releaseChunk",
            turtleName = State.turtleName,
            chunkNumber = State.chunkNumber
        }
        rednet.broadcast(textutils.serialize(data), "MT")
        log:logDebug(State.turtleName, "Released chunk " .. State.chunkNumber)
    end
end

function Communication.connectToMaster()
    print("Connecting to Master...")
    
    local data = {
        type = "newConnection",
        turtleName = State.turtleName,
        coordinates = {x = State.x, y = State.y, z = State.z},
        direction = State.direction,
        reconnect = (State.chunkNumber and State.chunkNumber > 0)
    }
    
    log:logDebug(State.turtleName, string.format(
        "Connecting from X:%d Y:%d Z:%d (reconnect: %s)", 
        State.x, State.y, State.z, tostring(data.reconnect)
    ))
    
    rednet.broadcast(textutils.serialize(data), "MT")
    
    local maxRetries = 10
    local retryCount = 0
    
    while retryCount < maxRetries do
        local id, msg = rednet.receive("C", 5)
        if msg then
            local config = textutils.unserialize(msg)
            log:logDebug(State.turtleName, "Received config, chunk: " .. config.chunkNumber)
            
            -- Update label if needed
            if not os.getComputerLabel() then
                os.setComputerLabel(config.turtleName)
                State.turtleName = config.turtleName
            end
            
            -- Apply configuration
            State.chunkNumber = config.chunkNumber
            State.startCoords.x = config.chunkCoordinates.startX
            State.startCoords.z = config.chunkCoordinates.startZ
            State.startCoords.y = config.currentChunkDepth
            State.startCoords.direction = config.startDirection or 1
            
            State.chestCoords = config.chestCoordinates
            State.trash = config.trash or {}
            
            -- Move to chunk start position
            Navigation.goToPosition(
                State.startCoords.x,
                State.startCoords.y,
                State.startCoords.z,
                State.startCoords.direction
            )
            
            log:logDebug(State.turtleName, "Positioned at chunk " .. config.chunkNumber)
            return
        end
        
        retryCount = retryCount + 1
        log:logDebug(State.turtleName, "No response, retry " .. retryCount .. "/" .. maxRetries)
        
        Utils.randomDelay(2, 4)
        rednet.broadcast(textutils.serialize(data), "MT")
    end
    
    error("Failed to connect to Master after " .. maxRetries .. " attempts")
end

-- ============================================================================
-- TURTLE DETECTION
-- ============================================================================

local TurtleDetection = {}

function TurtleDetection.isAhead()
    local success, data = turtle.inspect()
    return success and data and data.name == TURTLE_BLOCK_NAME
end

function TurtleDetection.isAbove()
    local success, data = turtle.inspectUp()
    return success and data and data.name == TURTLE_BLOCK_NAME
end

function TurtleDetection.isBelow()
    local success, data = turtle.inspectDown()
    return success and data and data.name == TURTLE_BLOCK_NAME
end

function TurtleDetection.waitForClearAhead(maxWait)
    maxWait = maxWait or WAIT_FOR_TURTLE_TIMEOUT
    local waited = 0
    
    while TurtleDetection.isAhead() and waited < maxWait do
        State.status = "Waiting for Turtle"
        Communication.sendUpdate()
        print("Turtle ahead, waiting...")
        
        local delay = 0.5 + math.random() * 1.5
        os.sleep(delay)
        waited = waited + delay
    end
    
    return not TurtleDetection.isAhead()
end

function TurtleDetection.waitForClearAbove(maxWait)
    maxWait = maxWait or WAIT_FOR_TURTLE_TIMEOUT
    local waited = 0
    
    while TurtleDetection.isAbove() and waited < maxWait do
        State.status = "Waiting for Turtle"
        Communication.sendUpdate()
        print("Turtle above, waiting...")
        
        local delay = 0.5 + math.random() * 1.5
        os.sleep(delay)
        waited = waited + delay
    end
    
    return not TurtleDetection.isAbove()
end

function TurtleDetection.waitForClearBelow(maxWait)
    maxWait = maxWait or WAIT_FOR_TURTLE_TIMEOUT
    local waited = 0
    
    while TurtleDetection.isBelow() and waited < maxWait do
        State.status = "Waiting for Turtle"
        Communication.sendUpdate()
        print("Turtle below, waiting...")
        
        local delay = 0.5 + math.random() * 1.5
        os.sleep(delay)
        waited = waited + delay
    end
    
    return not TurtleDetection.isBelow()
end

-- ============================================================================
-- MOVEMENT - Basic Actions
-- ============================================================================

local Movement = {}

function Movement.safeDig()
    if TurtleDetection.isAhead() then
        return false
    end
    return turtle.dig()
end

function Movement.safeDigUp()
    if TurtleDetection.isAbove() then
        return false
    end
    return turtle.digUp()
end

function Movement.safeDigDown()
    if TurtleDetection.isBelow() then
        return false
    end
    return turtle.digDown()
end

function Movement.turnRight()
    turtle.turnRight()
    State.direction = (State.direction % 4) + 1
    Communication.sendUpdate()
end

function Movement.turnLeft()
    turtle.turnLeft()
    State.direction = (State.direction - 2) % 4 + 1
    Communication.sendUpdate()
end

function Movement.turnTo(targetDir)
    local diff = (targetDir - State.direction) % 4
    if diff == 1 then
        turtle.turnRight()
    elseif diff == 2 then
        turtle.turnRight()
        turtle.turnRight()
    elseif diff == 3 then
        turtle.turnLeft()
    end
    State.direction = targetDir
    Communication.sendUpdate()
end

function Movement.updatePositionForward()
    if State.direction == DIRECTION.NORTH then
        State.z = State.z - 1
    elseif State.direction == DIRECTION.EAST then
        State.x = State.x + 1
    elseif State.direction == DIRECTION.SOUTH then
        State.z = State.z + 1
    elseif State.direction == DIRECTION.WEST then
        State.x = State.x - 1
    end
    Communication.sendUpdate()
end

-- ============================================================================
-- MOVEMENT - Avoidance Strategies
-- ============================================================================
function Movement.tryAvoidSideways()
    print("Attempting sideways avoidance...")

    local origDir = State.direction

    local function restoreDirection()
        while State.direction ~= origDir do
            Movement.turnLeft()
        end
    end

    local function moveForwardChecked()
        if TurtleDetection.isAhead() then return false end
        if not turtle.forward() then return false end
        Movement.updatePositionForward()
        return true
    end

    local function trySide(turnSide, turnBack)
        -- Step 1: move sideways
        turnSide()
        if not moveForwardChecked() then
            turnBack()
            return false
        end

        -- Step 2: face original direction and move forward
        turnBack()
        if not moveForwardChecked() then
            -- rollback sideways using only forward
            turnSide(); turnSide()
            if not moveForwardChecked() then return false end
            turnBack()
            restoreDirection()
            return false
        end

        -- Step 3: move back to original column
        turnSide()
        if not moveForwardChecked() then
            -- cannot safely restore → abort hard
            restoreDirection()
            return false
        end
        turnBack()

        restoreDirection()
        return true
    end

    -- Try right first
    if trySide(Movement.turnRight, Movement.turnLeft) then
        print("Successfully avoided via right")
        return true
    end

    -- Then left
    if trySide(Movement.turnLeft, Movement.turnRight) then
        print("Successfully avoided via left")
        return true
    end

    restoreDirection()
    print("Sideways avoidance failed")
    return false
end



function Movement.tryAvoidVertical()
    print("Attempting vertical avoidance...")
    
    Utils.randomDelay(0.5, 2)
    
    -- Try going up and around
    if not TurtleDetection.isAbove() and turtle.up() then
        State.y = State.y + 1
        Communication.sendUpdate()
        
        Utils.randomDelay(1, 3)
        
        if not TurtleDetection.isAhead() and turtle.forward() then
            Movement.updatePositionForward()
            
            if not TurtleDetection.isBelow() and turtle.down() then
                State.y = State.y - 1
                Communication.sendUpdate()
                print("Successfully avoided via up")
                return true
            else
                print("Avoided up, staying elevated")
                return true
            end
        else
            if not TurtleDetection.isBelow() then
                turtle.down()
                State.y = State.y - 1
                Communication.sendUpdate()
            end
        end
    end
    
    -- Try going down and around
    if not TurtleDetection.isBelow() and turtle.down() then
        State.y = State.y - 1
        Communication.sendUpdate()
        
        Utils.randomDelay(1, 3)
        
        if not TurtleDetection.isAhead() and turtle.forward() then
            Movement.updatePositionForward()
            
            if not TurtleDetection.isAbove() and turtle.up() then
                State.y = State.y + 1
                Communication.sendUpdate()
                print("Successfully avoided via down")
                return true
            else
                print("Avoided down, staying lower")
                return true
            end
        else
            if not TurtleDetection.isAbove() then
                turtle.up()
                State.y = State.y + 1
                Communication.sendUpdate()
            end
        end
    end
    
    print("Vertical avoidance failed")
    return false
end

-- ============================================================================
-- MOVEMENT - Primary Functions
-- ============================================================================

function Movement.up()
    local attempts = 0
    
    while attempts < MAX_MOVEMENT_ATTEMPTS do
        if State.currentCommand == "resumeMining" and State.status:find("Returning") then
            print("Movement interrupted by resumeMining!")
            error("COMMAND_OVERRIDE")
        end
        
        if TurtleDetection.isAbove() then
            if not TurtleDetection.waitForClearAbove(10) then
                if Movement.tryAvoidSideways() then
                    attempts = 0
                end
            end
        elseif turtle.detectUp() then
            Movement.safeDigUp()
        end
        
        if turtle.up() then
            State.y = State.y + 1
            Communication.sendUpdate()
            return true
        end
        
        attempts = attempts + 1
        Utils.randomDelay(0.3, 0.7)
    end
    
    error("Could not move up after " .. MAX_MOVEMENT_ATTEMPTS .. " attempts")
end

function Movement.down()
    local attempts = 0
    
    while attempts < MAX_MOVEMENT_ATTEMPTS do
        if State.currentCommand == "resumeMining" and State.status:find("Returning") then
            print("Movement interrupted by resumeMining!")
            error("COMMAND_OVERRIDE")
        end
        
        if TurtleDetection.isBelow() then
            if not TurtleDetection.waitForClearBelow(10) then
                if Movement.tryAvoidSideways() then
                    attempts = 0
                end
            end
        elseif turtle.detectDown() then
            Movement.safeDigDown()
        end
        
        if turtle.down() then
            State.y = State.y - 1
            Communication.sendUpdate()
            return true
        end
        
        attempts = attempts + 1
        Utils.randomDelay(0.3, 0.7)
    end
    
    error("Could not move down after " .. MAX_MOVEMENT_ATTEMPTS .. " attempts")
end

function Movement.forward()
    local attempts = 0
    
    while attempts < MAX_MOVEMENT_ATTEMPTS do
        if State.currentCommand == "resumeMining" and State.status:find("Returning") then
            print("Movement interrupted by resumeMining!")
            error("COMMAND_OVERRIDE")
        end
        
        if TurtleDetection.isAhead() then
            if not TurtleDetection.waitForClearAhead(10) then
                if not Movement.tryAvoidVertical() and not Movement.tryAvoidSideways() then
                    attempts = attempts + 1
                else
                    attempts = 0
                end
            end
        elseif turtle.detect() then
            Movement.safeDig()
        end
        
        if turtle.forward() then
            Movement.updatePositionForward()
            return true
        end
        
        attempts = attempts + 1
        Utils.randomDelay(0.3, 0.7)
    end
    
    error("Could not move forward after " .. MAX_MOVEMENT_ATTEMPTS .. " attempts")
end

-- ============================================================================
-- NAVIGATION
-- ============================================================================

Navigation = {}

function Navigation.goToPosition(targetX, targetY, targetZ, targetDir)
    State.status = "Going to Position"
    print(string.format(
        "Going to X:%d Y:%d Z:%d Dir:%s",
        targetX, targetY, targetZ, Utils.directionToString(targetDir)
    ))
    
    -- Move Y first
    while State.y < targetY do
        Movement.up()
    end
    while State.y > targetY do
        Movement.down()
    end
    
    -- Move X
    if targetX > State.x then
        Movement.turnTo(DIRECTION.EAST)
        while State.x < targetX do
            Movement.forward()
        end
    elseif targetX < State.x then
        Movement.turnTo(DIRECTION.WEST)
        while State.x > targetX do
            Movement.forward()
        end
    end
    
    -- Move Z
    if targetZ > State.z then
        Movement.turnTo(DIRECTION.SOUTH)
        while State.z < targetZ do
            Movement.forward()
        end
    elseif targetZ < State.z then
        Movement.turnTo(DIRECTION.NORTH)
        while State.z > targetZ do
            Movement.forward()
        end
    end
    
    Movement.turnTo(targetDir)
end

function Navigation.detectDirection()
    local function testMovement(turnBefore, turnAfter)
        if turnBefore then turnBefore() end
        
        local x1, y1, z1 = Utils.stableGPS()
        if not x1 then
            if turnAfter then turnAfter() end
            return nil
        end
        
        Movement.forward()
        os.sleep(1)
        
        local x2, y2, z2 = Utils.stableGPS()
        if not x2 then
            if turnAfter then turnAfter() end
            return nil
        end
        
        -- Return to original position
        Movement.turnLeft()
        Movement.turnLeft()
        Movement.forward()
        Movement.turnLeft()
        Movement.turnLeft()
        
        if turnAfter then turnAfter() end
        
        local dx = x2 - x1
        local dz = z2 - z1
        
        if math.abs(dx) > math.abs(dz) then
            return dx > 0 and DIRECTION.EAST or DIRECTION.WEST
        elseif math.abs(dz) > math.abs(dx) then
            return dz > 0 and DIRECTION.SOUTH or DIRECTION.NORTH
        end
        return nil
    end
    
    local maxAttempts = 8
    for attempt = 1, maxAttempts do
        print("Detecting direction... (attempt " .. attempt .. "/" .. maxAttempts .. ")")
        
        local dir = testMovement(nil, nil)
        if dir then return dir end
        
        dir = testMovement(Movement.turnLeft, Movement.turnRight)
        if dir then return dir end
        
        dir = testMovement(Movement.turnRight, Movement.turnLeft)
        if dir then return dir end
        
        os.sleep(1)
    end
    
    print("Warning: Could not detect direction, using current")
    return State.direction
end

function Navigation.parkAtBase()
    local turtleNum = tonumber(State.turtleName:match("%d+")) or 1
    
    local gridSize = 4
    local spacing = 1
    
    local row = math.floor((turtleNum - 1) / gridSize)
    local col = (turtleNum - 1) % gridSize
    
    local offsetX = col * spacing
    local offsetZ = row * spacing
    
    local parkX = State.chestCoords.x + offsetX
    local parkZ = State.chestCoords.z + offsetZ
    local parkY = State.chestCoords.y - 1
    
    print(string.format("Parking at grid position [%d,%d]: X:%d Z:%d", row, col, parkX, parkZ))
    
    Navigation.goToPosition(parkX, parkY, parkZ, State.chestCoords.direction)
end

-- ============================================================================
-- INVENTORY MANAGEMENT
-- ============================================================================

local Inventory = {}

function Inventory.dropTrash()
    State.status = "Dropping Trash"
    Communication.sendUpdate()
    
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and State.trash[item.name] then
            turtle.select(i)
            turtle.dropDown()
        end
    end
end

function Inventory.sort()
    for i = 1, 16 do
        local itemI = turtle.getItemDetail(i)
        if itemI then
            for j = i + 1, 16 do
                local itemJ = turtle.getItemDetail(j)
                if itemJ and itemI.name == itemJ.name then
                    turtle.select(j)
                    turtle.transferTo(i)
                end
            end
        end
    end
    
    for i = 1, 16 do
        if turtle.getItemCount(i) == 0 then
            for j = i + 1, 16 do
                if turtle.getItemCount(j) > 0 then
                    turtle.select(j)
                    turtle.transferTo(i)
                    break
                end
            end
        end
    end
    
    turtle.select(1)
end

function Inventory.isFull()
    for i = 1, 16 do
        if turtle.getItemCount(i) == 0 then
            return false
        end
    end
    
    Inventory.sort()
    Inventory.dropTrash()
    
    for i = 1, 16 do
        if turtle.getItemCount(i) == 0 then
            return false
        end
    end
    
    return true
end

function Inventory.refuel()
    State.status = "Refueling"
    Communication.sendUpdate()
    
    for slot = 1, 16 do
        turtle.select(slot)
        local count = turtle.getItemCount(slot)
        if count > 0 and turtle.refuel(0) then
            turtle.refuel(count)
            print("Refueled with slot " .. slot)
        end
    end
    
    turtle.select(1)
end

function Inventory.unload()
    for i = 1, 16 do
        State.status = "Unloading"
        Communication.sendUpdate()
        turtle.select(i)
        turtle.dropUp()
    end
    turtle.select(1)
end

function Inventory.checkAndUnload()
    if Inventory.isFull() then
        Inventory.refuel()
        
        local x, y, z, dir = State.x, State.y, State.z, State.direction
        Navigation.goToPosition(
            State.chestCoords.x,
            State.chestCoords.y - 1,
            State.chestCoords.z,
            State.chestCoords.direction
        )
        
        Inventory.unload()
        Movement.turnLeft()
        Movement.turnLeft()
        
        Navigation.goToPosition(x, y, z, dir)
    end
end

-- ============================================================================
-- COMMAND SYSTEM
-- ============================================================================

local Commands = {}

function Commands.listen()
    while true do
        local id, msg = rednet.receive("TURTLE_CMD")
        if msg then
            local success, message = pcall(textutils.unserialize, msg)
            if success and message.type == "command" then
                State.currentCommand = message.command
                State.commandHandled = false
                log:logDebug(State.turtleName, "Received command: " .. message.command)
                print(">>> COMMAND: " .. message.command .. " <<<")
            end
        end
        os.sleep(0.1)
    end
end

function Commands.execute()
    if not State.currentCommand or State.commandHandled then
        return false
    end
    
    local cmd = State.currentCommand
    print("Executing: " .. cmd)
    State.status = "Command: " .. cmd
    Communication.sendUpdate()
    
    local success, err
    
    if cmd == "returnToBase" then
        success, err = pcall(Commands.returnToBase)
        
        if not success then
            local errStr = tostring(err)
            if errStr:find("COMMAND_OVERRIDE") or errStr:find("RESTART_MINING") then
                print("returnToBase was interrupted!")
                if State.currentCommand ~= cmd then
                    print("New command detected: " .. State.currentCommand)
                    State.commandHandled = false
                    return Commands.execute()
                end
            else
                error(err)
            end
        end
        
        if State.currentCommand ~= cmd then
            print("New command detected after returnToBase: " .. State.currentCommand)
            State.commandHandled = false
            return Commands.execute()
        end
        
    elseif cmd == "resumeMining" then
        Commands.resumeMining()
    end
    
    State.commandHandled = true
    State.currentCommand = nil
    return true
end

function Commands.returnToBase()
    State.status = "Returning to Base"
    Communication.sendUpdate()
    print("Going to base...")
    
    local success, err = pcall(function()
        Navigation.parkAtBase()
    end)
    
    if not success then
        local errStr = tostring(err)
        if errStr:find("COMMAND_OVERRIDE") or errStr:find("RESTART_MINING") then
            print("returnToBase interrupted by new command!")
            error(err)
        else
            error(err)
        end
    end
    
    State.status = "At Base"
    Communication.sendUpdate()
    print("At base. Waiting for commands...")
    
    local waitCount = 0
    while State.currentCommand == "returnToBase" do
        os.sleep(1)
        waitCount = waitCount + 1
        if waitCount % 10 == 0 then
            print("Still waiting... (" .. waitCount .. "s)")
        end
    end
    
    print("Wait ended. Current command: " .. tostring(State.currentCommand))
end

function Commands.resumeMining()
    State.status = "Resuming Mining"
    Communication.sendUpdate()
    
    log:logDebug(State.turtleName, "Starting resumeMining - releasing chunk " .. State.chunkNumber)
    
    -- Release current chunk
    Communication.releaseChunk()
    
    -- FIX: Random delay to prevent all turtles reconnecting simultaneously
    -- Different turtles will wait different amounts of time (3-8 seconds)
    local delay = 3 + math.random() * 5
    log:logDebug(State.turtleName, string.format("Waiting %.1f seconds before reconnecting", delay))
    
    for i = 1, math.ceil(delay) do
        os.sleep(1)
        if i % 2 == 0 then
            print(string.format("Reconnecting in %d seconds...", math.ceil(delay) - i))
        end
    end
    
    -- Clear chunk number AFTER releasing and waiting
    State.chunkNumber = 0
    State.restartMining = true
    
    -- Clear command state
    State.currentCommand = nil
    State.commandHandled = true
    
    log:logDebug(State.turtleName, "Ready to reconnect and get new chunk")
    
    error("RESTART_MINING")
end

function Commands.check()
    if State.currentCommand and not State.commandHandled then
        return Commands.execute()
    end
    return false
end

-- ============================================================================
-- MINING OPERATIONS
-- ============================================================================

local Mining = {}

function Mining.strip(length)
    for i = 1, length do
        if State.restartMining then
            return false
        end
        
        if Commands.check() then
            if State.currentCommand == "pauseMining" or 
               State.currentCommand == "emergencyStop" or 
               State.restartMining then
                return false
            end
        end
        
        State.status = "Mining"
        Communication.sendUpdate()
        
        Inventory.checkAndUnload()
        
        Movement.safeDigUp()
        Movement.safeDigDown()
        Movement.forward()
        Movement.safeDigUp()
        Movement.safeDigDown()
    end
    return true
end

function Mining.tripleLayer(length, width)
    for x = 1, length do
        if State.restartMining then
            return false
        end
        
        if Commands.check() then
            if State.currentCommand == "pauseMining" or 
               State.currentCommand == "emergencyStop" or 
               State.restartMining then
                return false
            end
        end
        
        if not Mining.strip(width - 1) then
            return false
        end
        
        if x < length then
            Movement.safeDigUp()
            Movement.safeDigDown()
            
            if x % 2 == 1 then
                Movement.turnRight()
                Movement.forward()
                Movement.turnRight()
            else
                Movement.turnLeft()
                Movement.forward()
                Movement.turnLeft()
            end
            
            Movement.safeDigUp()
            Movement.safeDigDown()
        end
    end
    
    Navigation.goToPosition(State.startCoords.x, State.y, State.startCoords.z, DIRECTION.EAST)
    return true
end

function Mining.quarry(length, width, height)
    local layers = math.ceil(height / 3)
    
    for i = 1, layers do
        if State.restartMining then
            return false
        end
        
        if Commands.check() then
            if State.currentCommand == "pauseMining" or 
               State.currentCommand == "emergencyStop" or 
               State.restartMining then
                return false
            end
        end
        
        Communication.sendLayerUpdate(State.y)
        
        if not Mining.tripleLayer(length, width) then
            return false
        end
        
        if i < layers and State.y > -60 then
            for d = 1, 3 do
                Movement.down()
            end
        end
    end
    
    return true
end

-- ============================================================================
-- MAIN PROGRAM
-- ============================================================================

local function main()
    Utils.updateGPS()
    State.direction = Navigation.detectDirection()
    
    if not State.x or not State.y or not State.z or not State.direction then
        error("Could not determine initial position or direction")
    end
    
    print(string.format(
        "Starting at X:%d Y:%d Z:%d facing %s",
        State.x, State.y, State.z, Utils.directionToString(State.direction)
    ))
    
    parallel.waitForAny(
        Commands.listen,
        function()
            while true do
                State.restartMining = false
                
                local success, err = pcall(function()
                    Communication.connectToMaster()
                    Utils.sleep(3)
                    
                    print("Starting quarry operation...")
                    local miningSuccess = Mining.quarry(16, 16, State.startCoords.y)
                    
                    if not miningSuccess then
                        if State.restartMining then
                            print("Mining restart triggered")
                        else
                            print("Quarry interrupted, waiting for resume...")
                            while State.currentCommand == "pauseMining" or 
                                  State.currentCommand == "emergencyStop" or 
                                  State.currentCommand == "returnToBase" do
                                os.sleep(1)
                                
                                if (os.epoch("utc") % 10000) < 1000 then
                                    print("Waiting... Current command: " .. tostring(State.currentCommand))
                                end
                            end
                            print("Wait loop ended. Checking for resumeMining...")
                            
                            if State.currentCommand == "resumeMining" then
                                print("Executing resumeMining from wait loop...")
                                Commands.execute()
                            end
                        end
                    else
                        print("Chunk completed, requesting new chunk...")
                        sleep(2)
                    end
                end)
                
                if not success then
                    local errStr = tostring(err)
                    if errStr:find("RESTART_MINING") or errStr:find("COMMAND_OVERRIDE") then
                        print("Restarting mining loop with new chunk...")
                    else
                        print("Real error occurred: " .. errStr)
                        error(err)
                    end
                end
            end
        end
    )
end

main()