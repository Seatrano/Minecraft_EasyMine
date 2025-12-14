local DeviceFinder = require("helper.getDevices")
local finder = DeviceFinder.new()
local logger = require("helper.logger")
local log = logger.new()
finder:openModem()


local computerId = os.getComputerID()
local turtleName = os.getComputerLabel()
local currentX, currentY, currentZ
local direction = 2
local status = "Idle"
local chunkNumber = 0
local startCoords = {
    x = 0,
    y = 0,
    z = 0,
    direction = 1
}

local chestCoords = {}
local trash = {}

-- BEFEHLSSYSTEM
local currentCommand = nil
local commandHandled = false

local function sleepForSeconds(seconds)
    for i = 1, seconds do
        print("Sleeping... " .. (seconds - i + 1) .. "s remaining")
        os.sleep(1)
    end
end

local function getGPS(timeout)
    timeout = timeout or 5

    while true do
        local x, y, z = gps.locate(timeout)
        if x and z then
            return x, y, z
        end
        print("GPS nicht verfügbar, warte 1 Sekunde...")
        sleepForSeconds(1)
    end
end

local function sendMessage()
    local data = {
        type = "update",
        coordinates = {
            x = currentX,
            y = currentY,
            z = currentZ
        },
        fuelLevel = turtle.getFuelLevel(),
        direction = direction,
        status = status,
        turtleName = turtleName,
        chunkNumber = chunkNumber
    }
    local serializedData = textutils.serialize(data)
    rednet.broadcast(serializedData, "MT")
end

local function dropTrash()
    status = "Dropping Trash"
    sendMessage()
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and trash[item.name] then
            turtle.select(i)
            turtle.dropDown()
        end
    end
end

local function sortInventory()
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

local function isInventoryFull()
    for i = 1, 16 do
        if turtle.getItemCount(i) == 0 then
            return false
        end
    end

    sortInventory()
    dropTrash()

    for i = 1, 16 do
        if turtle.getItemCount(i) == 0 then
            return false
        end
    end

    return true
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
        return "Unknown"
    end
end

local function turnRight()
    turtle.turnRight()
    sendMessage()
    direction = (direction % 4) + 1
end

local function turnLeft()
    turtle.turnLeft()
    sendMessage()
    direction = (direction - 2) % 4 + 1
end

local function turnTo(targetDir)
    local diff = (targetDir - direction) % 4
    if diff == 1 then
        turtle.turnRight()
    elseif diff == 2 then
        turtle.turnRight()
        turtle.turnRight()
    elseif diff == 3 then
        turtle.turnLeft()
    end
    sendMessage()
    direction = targetDir
end

-- ============================================================================
-- SICHERE TURTLE-ERKENNUNG UND AUSWEICH-FUNKTIONEN
-- ============================================================================

local function isTurtleAhead()
    local success, data = turtle.inspect()
    if success and data and data.name == "computercraft:turtle_advanced" then
        return true
    end
    return false
end

local function isTurtleUp()
    local success, data = turtle.inspectUp()
    if success and data and data.name == "computercraft:turtle_advanced" then
        return true
    end
    return false
end

local function isTurtleDown()
    local success, data = turtle.inspectDown()
    if success and data and data.name == "computercraft:turtle_advanced" then
        return true
    end
    return false
end

-- SICHERE DIG-FUNKTIONEN: Niemals eine Turtle abbauen!
local function safeDig()
    if isTurtleAhead() then
        return false -- Turtle im Weg - nicht abbauen!
    end
    return turtle.dig()
end

local function safeDigUp()
    if isTurtleUp() then
        return false -- Turtle im Weg - nicht abbauen!
    end
    return turtle.digUp()
end

local function safeDigDown()
    if isTurtleDown() then
        return false -- Turtle im Weg - nicht abbauen!
    end
    return turtle.digDown()
end

-- Wartet bis der Weg frei ist
local function waitForClearAhead(maxWait)
    maxWait = maxWait or 30
    local waited = 0
    
    while isTurtleAhead() and waited < maxWait do
        status = "Waiting for Turtle"
        sendMessage()
        print("Turtle ahead detected, waiting...")
        os.sleep(1)
        waited = waited + 1
    end
    
    return not isTurtleAhead()
end

local function waitForClearUp(maxWait)
    maxWait = maxWait or 30
    local waited = 0
    
    while isTurtleUp() and waited < maxWait do
        status = "Waiting for Turtle"
        sendMessage()
        print("Turtle above detected, waiting...")
        os.sleep(1)
        waited = waited + 1
    end
    
    return not isTurtleUp()
end

local function waitForClearDown(maxWait)
    maxWait = maxWait or 30
    local waited = 0
    
    while isTurtleDown() and waited < maxWait do
        status = "Waiting for Turtle"
        sendMessage()
        print("Turtle below detected, waiting...")
        os.sleep(1)
        waited = waited + 1
    end
    
    return not isTurtleDown()
end

-- Ausweich-Manöver: Versuche seitlich auszuweichen
local function tryAvoidSideways()
    print("Attempting sideways avoidance...")
    
    -- Versuche nach rechts
    turnRight()
    if not isTurtleAhead() then
        if turtle.forward() then
            os.sleep(2) -- Warte kurz
            turnLeft()
            if not isTurtleAhead() and turtle.forward() then
                turnLeft()
                if not isTurtleAhead() and turtle.forward() then
                    turnRight()
                    return true
                end
            end
        end
    end
    turnLeft() -- Zurück zur ursprünglichen Richtung
    
    -- Versuche nach links
    turnLeft()
    if not isTurtleAhead() then
        if turtle.forward() then
            os.sleep(2)
            turnRight()
            if not isTurtleAhead() and turtle.forward() then
                turnRight()
                if not isTurtleAhead() and turtle.forward() then
                    turnLeft()
                    return true
                end
            end
        end
    end
    turnRight() -- Zurück zur ursprünglichen Richtung
    
    return false
end

-- ============================================================================
-- VERBESSERTE BEWEGUNGS-FUNKTIONEN
-- ============================================================================

local function up()
    local attempts = 0
    local maxAttempts = 60
    
    while attempts < maxAttempts do
        if isTurtleUp() then
            print("Turtle above - waiting...")
            if not waitForClearUp(10) then
                -- Nach 10 Sekunden warten, versuche auszuweichen
                if tryAvoidSideways() then
                    attempts = 0 -- Reset nach erfolgreichem Ausweichen
                end
            end
        elseif turtle.detectUp() then
            safeDigUp()
        end

        if turtle.up() then
            currentY = currentY + 1
            sendMessage()
            return true
        end
        
        attempts = attempts + 1
        os.sleep(0.5)
    end
    
    error("Could not move up after " .. maxAttempts .. " attempts")
end

local function down()
    local attempts = 0
    local maxAttempts = 60
    
    while attempts < maxAttempts do
        if isTurtleDown() then
            print("Turtle below - waiting...")
            if not waitForClearDown(10) then
                if tryAvoidSideways() then
                    attempts = 0
                end
            end
        elseif turtle.detectDown() then
            safeDigDown()
        end

        if turtle.down() then
            currentY = currentY - 1
            sendMessage()
            return true
        end
        
        attempts = attempts + 1
        os.sleep(0.5)
    end
    
    error("Could not move down after " .. maxAttempts .. " attempts")
end

local function forward()
    local attempts = 0
    local maxAttempts = 60
    
    while attempts < maxAttempts do
        if isTurtleAhead() then
            print("Turtle ahead - waiting...")
            if not waitForClearAhead(10) then
                -- Versuche vertikales Ausweichen
                print("Attempting vertical avoidance...")
                if not isTurtleUp() and turtle.up() then
                    currentY = currentY + 1
                    sendMessage()
                    os.sleep(2)
                    if not isTurtleAhead() and turtle.forward() then
                        -- Erfolgreich ausgewichen, gehe zurück runter
                        if direction == 1 then currentZ = currentZ - 1
                        elseif direction == 2 then currentX = currentX + 1
                        elseif direction == 3 then currentZ = currentZ + 1
                        elseif direction == 4 then currentX = currentX - 1 end
                        sendMessage()
                        
                        if not isTurtleDown() and turtle.down() then
                            currentY = currentY - 1
                            sendMessage()
                            return true
                        end
                    else
                        -- Ausweichen fehlgeschlagen, zurück
                        if not isTurtleDown() then
                            turtle.down()
                            currentY = currentY - 1
                            sendMessage()
                        end
                    end
                end
                attempts = 0 -- Reset nach Ausweichversuch
            end
        elseif turtle.detect() then
            safeDig()
        end

        if turtle.forward() then
            if direction == 1 then currentZ = currentZ - 1
            elseif direction == 2 then currentX = currentX + 1
            elseif direction == 3 then currentZ = currentZ + 1
            elseif direction == 4 then currentX = currentX - 1 end
            sendMessage()
            return true
        end
        
        attempts = attempts + 1
        os.sleep(0.5)
    end
    
    error("Could not move forward after " .. maxAttempts .. " attempts")
end

-- ============================================================================
-- RESTLICHER CODE (Navigation, GPS, etc.)
-- ============================================================================

local function detectDirectionFromDelta(dx, dz)
    if math.abs(dx) > math.abs(dz) then
        return dx > 0 and 2 or 4
    elseif math.abs(dz) > math.abs(dx) then
        return dz > 0 and 3 or 1
    end
    return nil
end

local function stableGPS()
    while true do
        print("Acquiring stable GPS...")
        local x, y, z = gps.locate(1)
        if x and z then
            return x, y, z
        end
        os.sleep(1)
    end
end

local function testMovement(turnBefore, turnAfter)
    if turnBefore then
        turnBefore()
    end

    local x1, y1, z1 = stableGPS()
    print("GPS before move: ", x1, y1, z1)
    if not x1 then
        if turnAfter then
            turnAfter()
        end
        return nil
    end

    forward()

    os.sleep(1)
    local x2, y2, z2 = stableGPS()
    print("GPS after move: ", x2, y2, z2)
    if not x2 then
        if turnAfter then
            turnAfter()
        end
        return nil
    end

    turnLeft()
    turnLeft()
    forward()
    turnLeft()
    turnLeft()

    if turnAfter then
        turnAfter()
    end

    local dx = x2 - x1
    local dz = z2 - z1
    return detectDirectionFromDelta(dx, dz)
end

local function getDirection()
    local maxAttempts = 8
    for attempt = 1, maxAttempts do
        print("Attempting to detect direction... (attempt " .. attempt .. "/" .. maxAttempts .. ")")
        sendMessage()

        local dir = testMovement(nil, nil)
        if dir then
            print("Direction detected: " .. directionToString(dir))
            return dir
        end

        dir = testMovement(function()
            turnLeft()
        end, function()
            turnRight()
        end)

        if dir then
            print("Direction detected (left): " .. directionToString(dir))
            return dir
        end

        dir = testMovement(function()
            turnRight()
        end, function()
            turnLeft()
        end)

        if dir then
            print("Direction detected (right): " .. directionToString(dir))
            return dir
        end

        print("No valid direction detected on this attempt. Retrying in 1 second...")
        os.sleep(1)
    end

    print("Warning: Could not detect direction after " .. maxAttempts ..
              " attempts. Falling back to current direction: " .. directionToString(direction))
    return direction
end

local function goToPosition(targetX, targetY, targetZ, targetDir)
    status = "Going to Position"
    print("Going to X:" .. targetX .. " Y:" .. targetY .. " Z:" .. targetZ .. " Dir:" .. directionToString(targetDir))

    -- Y-Bewegung
    while currentY < targetY do
        up()
    end

    while currentY > targetY do
        down()
    end

    -- X-Bewegung
    if targetX > currentX then
        turnTo(2)
        while currentX < targetX do
            forward()
        end
    elseif targetX < currentX then
        turnTo(4)
        while currentX > targetX do
            forward()
        end
    end

    -- Z-Bewegung
    if targetZ > currentZ then
        turnTo(3)
        while currentZ < targetZ do
            forward()
        end
    elseif targetZ < currentZ then
        turnTo(1)
        while currentZ > targetZ do
            forward()
        end
    end

    turnTo(targetDir)
    sendMessage()
end

local function connectToMaster()
    print("Connecting to Master...")

    local data = {
        type = "newConnection",
        turtleName = turtleName,
        coordinates = {
            x = currentX,
            y = currentY,
            z = currentZ
        },
        direction = direction
    }

    log:logDebug(turtleName, "Connecting to Master from X:" .. currentX .. " Y:" .. currentY .. " Z:" .. currentZ)

    rednet.broadcast(textutils.serialize(data), "MT")

    while true do
        local id, msg = rednet.receive("C")
        if msg then
            local dataReceived = textutils.unserialize(msg)
            log:logDebug(turtleName, "Received config from Master, chunkNumber: " .. dataReceived.chunkNumber)

            if os.getComputerLabel() == nil then
                log:logDebug(turtleName, "Setting computer label to " .. dataReceived.turtleName)
                os.setComputerLabel(dataReceived.turtleName)
                turtleName = dataReceived.turtleName
            end

            chunkNumber = dataReceived.chunkNumber

            startCoords.x = dataReceived.chunkCoordinates.startX
            startCoords.z = dataReceived.chunkCoordinates.startZ
            startCoords.y = dataReceived.currentChunkDepth
            startCoords.direction = dataReceived.startDirection or 1

            chestCoords.x = dataReceived.chestCoordinates.x
            chestCoords.y = dataReceived.chestCoordinates.y
            chestCoords.z = dataReceived.chestCoordinates.z
            chestCoords.direction = dataReceived.chestCoordinates.direction

            trash = dataReceived.trash or {}

            goToPosition(startCoords.x, startCoords.y, startCoords.z, startCoords.direction)

            log:logDebug(turtleName, "Going to chunk " .. dataReceived.chunkNumber)
            break
        else
            log:logDebug(turtleName, "No response from Master, retrying in 3 seconds...")
            sleep(3)
        end
    end
end

local function refuel()
    status = "Refueling"
    sendMessage()

    for slot = 1, 16 do
        turtle.select(slot)
        local count = turtle.getItemCount(slot)

        if count > 0 then
            if turtle.refuel(0) then
                turtle.refuel(count)
                print("Refueled with slot " .. slot .. " (" .. count .. " items)")
            end
        end
    end

    turtle.select(1)
end

local function unload()
    for i = 1, 16 do
        status = "Unloading"
        sendMessage()
        turtle.select(i)
        turtle.dropUp()
    end
    turtle.select(1)
end

local function updateForComputer(height)
    local data = {
        type = "updateLayer",
        turtleName = turtleName,
        height = height,
        chunkNumber = chunkNumber
    }
    rednet.broadcast(textutils.serialize(data), "MT")
end

-- ============================================================================
-- BEFEHLSSYSTEM
-- ============================================================================

-- Lauscht kontinuierlich auf Befehle vom Master
local function commandListener()
    while true do
        local id, msg = rednet.receive("TURTLE_CMD", 0.5)
        if msg then
            local success, message = pcall(textutils.unserialize, msg)
            if success and message.type == "command" then
                currentCommand = message.command
                commandHandled = false
                log:logDebug(turtleName, "Received command: " .. message.command)
                print(">>> COMMAND RECEIVED: " .. message.command .. " <<<")
            end
        end
        os.sleep(0.1)
    end
end

-- Führt den aktuellen Befehl aus
local function executeCommand()
    if not currentCommand or commandHandled then
        return false
    end
    
    print("Executing command: " .. currentCommand)
    status = "Command: " .. currentCommand
    sendMessage()
    
    if currentCommand == "returnToBase" then
        status = "Returning to Base"
        sendMessage()
        
        -- Gehe zur Chest (eine Position darunter)
        local baseX = chestCoords.x
        local baseY = chestCoords.y - 1
        local baseZ = chestCoords.z
        local baseDir = chestCoords.direction
        
        log:logDebug(turtleName, "Going to base at X:" .. baseX .. " Y:" .. baseY .. " Z:" .. baseZ)
        goToPosition(baseX, baseY, baseZ, baseDir)
        
        status = "At Base"
        sendMessage()
        print("Arrived at base. Waiting for further commands...")
        
        -- Warte auf Resume-Befehl
        while currentCommand == "returnToBase" do
            os.sleep(1)
        end
        
    elseif currentCommand == "resumeMining" then
        status = "Resuming Mining"
        sendMessage()
        print("Resuming mining operations...")
        
        -- Gehe zurück zur letzten Mining-Position
        goToPosition(startCoords.x, startCoords.y, startCoords.z, startCoords.direction)
        
    elseif currentCommand == "pauseMining" then
        status = "Paused"
        sendMessage()
        print("Mining paused. Waiting for resume command...")
        
        -- Warte auf Resume
        while currentCommand == "pauseMining" do
            os.sleep(1)
        end
        
    elseif currentCommand == "emergencyStop" then
        status = "Emergency Stop"
        sendMessage()
        print("EMERGENCY STOP activated!")
        
        -- Stoppe alle Operationen
        while currentCommand == "emergencyStop" do
            os.sleep(1)
        end
        
    elseif currentCommand == "refuelAll" then
        status = "Refueling"
        sendMessage()
        refuel()
        status = "Refueled"
        sendMessage()
        
    elseif currentCommand == "unloadAll" then
        status = "Unloading Inventory"
        sendMessage()
        
        local x, y, z, dir = currentX, currentY, currentZ, direction
        goToPosition(chestCoords.x, chestCoords.y - 1, chestCoords.z, chestCoords.direction)
        unload()
        turnLeft()
        turnLeft()
        goToPosition(x, y, z, dir)
        
        status = "Inventory Unloaded"
        sendMessage()
        
    elseif currentCommand == "statusReport" then
        status = "Reporting Status"
        sendMessage()
        
        print("Status Report:")
        print("  Position: X:" .. currentX .. " Y:" .. currentY .. " Z:" .. currentZ)
        print("  Direction: " .. directionToString(direction))
        print("  Fuel: " .. turtle.getFuelLevel())
        print("  Chunk: " .. chunkNumber)
        
        status = "Online"
        sendMessage()
    end
    
    commandHandled = true
    currentCommand = nil
    return true
end

-- Prüft ob ein Befehl ausgeführt werden muss
local function checkForCommands()
    if currentCommand and not commandHandled then
        return executeCommand()
    end
    return false
end

local function mineStrip(length)
    for i = 1, length do
        -- Prüfe auf Befehle vor jedem Schritt
        if checkForCommands() then
            -- Befehl wurde ausgeführt, setze fort
            if currentCommand == "pauseMining" or currentCommand == "emergencyStop" then
                return false -- Mining unterbrochen
            end
        end
        
        status = "Mining"
        sendMessage()
        
        if isInventoryFull() then
            refuel()
            local x, y, z, dir = currentX, currentY, currentZ, direction
            goToPosition(chestCoords.x, chestCoords.y - 1, chestCoords.z, chestCoords.direction)
            unload()
            turnLeft()
            turnLeft()
            goToPosition(x, y, z, dir)
        end
        
        -- SICHERE Mining-Operationen
        safeDigUp()
        safeDigDown()
        forward()
        safeDigUp()
        safeDigDown()
    end
    return true
end

local function mineTripleLayer(length, width)
    for x = 1, length do
        -- Prüfe auf Befehle
        if checkForCommands() then
            if currentCommand == "pauseMining" or currentCommand == "emergencyStop" then
                return false
            end
        end
        
        if not mineStrip(width - 1) then
            return false -- Unterbrochen
        end

        if x < length then
            if x % 2 == 1 then
                safeDigUp()
                safeDigDown()
                turnRight()
                forward()
                turnRight()
                safeDigUp()
                safeDigDown()
            else
                safeDigUp()
                safeDigDown()
                turnLeft()
                forward()
                turnLeft()
                safeDigUp()
                safeDigDown()
            end
        end
    end

    goToPosition(startCoords.x, currentY, startCoords.z, 2)
    return true
end

local function quarry(length, width, height, startDirection)
    local layers = math.ceil(height / 3)

    for i = 1, layers do
        -- Prüfe auf Befehle vor jeder Layer
        if checkForCommands() then
            if currentCommand == "pauseMining" or currentCommand == "emergencyStop" then
                print("Mining interrupted by command")
                return false
            end
        end
        
        updateForComputer(currentY)
        
        if not mineTripleLayer(length, width) then
            print("Layer interrupted")
            return false
        end

        if i < layers then
            for d = 1, 3 do
                if currentY > -60 then
                    down()
                end
            end
        end
    end
    return true
end

-- ============================================================================
-- PROGRAM START
-- ============================================================================

while true do
    currentX, currentY, currentZ = getGPS(5)
    sendMessage()
    if currentX then
        break
    end
    print("GPS fehlt – warte bis die Welt komplett geladen ist...")
    sleep(1)
end

direction = getDirection()
if currentX and currentY and currentZ and direction then

    print("Starting at X:" .. currentX .. " Y:" .. currentY .. " Z:" .. currentZ,
        "facing direction:" .. directionToString(direction))

    -- Haupt-Loop mit parallelem Command-Listening
    parallel.waitForAny(
        -- Command Listener läuft kontinuierlich
        commandListener,
        
        -- Mining-Loop
        function()
            while true do
                connectToMaster()
                sleepForSeconds(3)
                
                -- Starte Mining
                print("Starting quarry operation...")
                local success = quarry(16, 16, startCoords.y, direction)
                
                if not success then
                    print("Quarry interrupted. Waiting for resume...")
                    -- Warte bis Resume-Befehl kommt
                    while currentCommand == "pauseMining" or currentCommand == "emergencyStop" or currentCommand == "returnToBase" do
                        os.sleep(1)
                    end
                end
                
                -- Chunk fertig - neuen anfordern
                print("Chunk completed. Requesting new chunk...")
                sleep(2)
            end
        end
    )

else
    print("Could not determine initial position or direction. Aborting.")
end