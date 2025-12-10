local DeviceFinder = require("helper.getDevices")
local finder = DeviceFinder.new()
local logger = require("helper.logger")
local log = logger.new()
finder:openModem()

local trash = {
    ["minecraft:cobblestone"] = true,
    ["minecraft:dirt"] = true,
    ["minecraft:andesite"] = true,
    ["minecraft:diorite"] = true,
    ["create:limestone_cobblestone"] = true,
    ["minecraft:gravel"] = true,
    ["minecraft:granite"] = true,
    ["minecraft:cobbled_deepslate"] = true
}

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

local function sleepForSeconds(seconds)
    for i = 1, seconds do
        print("Sleeping... " .. (seconds - i + 1) .. "s remaining")
        os.sleep(1)
    end
end

local function getGPS(timeout)
    timeout = timeout or 5 -- Sekunden für gps.locate()

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
    -- 1) Stacks zusammenführen
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

    -- 2) Leere Slots nach hinten schieben
    -- Wir gehen von vorne nach hinten und holen das nächste Item von hinten nach vorne
    for i = 1, 16 do
        if turtle.getItemCount(i) == 0 then
            -- Suche nächstes Item hinter diesem Slot
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

-- Prüft, ob Inventory voll ist, sortiert Items und schmeißt Trash weg
local function isInventoryFull()
    for i = 1, 16 do
        if turtle.getItemCount(i) == 0 then
            return false
        end
    end

    -- inventory ist voll -> sortieren und trash droppen
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

-- Dreht die Turtle nach rechts und aktualisiert currentDir
local function turnRight()
    turtle.turnRight()
    sendMessage()
    direction = (direction % 4) + 1 -- Nord(1)->Ost(2)->Süd(3)->West(4)->Nord(1)
end

-- Dreht die Turtle nach links und aktualisiert currentDir
local function turnLeft()
    turtle.turnLeft()
    sendMessage()
    direction = (direction - 2) % 4 + 1 -- Nord(1)->West(4)->Süd(3)->Ost(2)->Nord(1)
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

local function avoidTurtleByYAxis()
    if direction == 1 or direction == 2 then
        -- Ausweichen nach unten
        while true do
            if not isTurtleDown() then
                if not turtle.down() then
                    turtle.digDown()
                else
                    break
                end
            end
            sleepForSeconds(1)
        end

        sleepForSeconds(3)

        -- Ausweichen nach oben
        while true do
            if not isTurtleUp() then
                if not turtle.up() then
                    turtle.digUp()
                else
                    break
                end
            end
            sleepForSeconds(1)
        end
    else
        sleepForSeconds(1)
    end
end

local function avoidTurtleByForward()
    if direction == 1 or direction == 2 then
        while true do
            if not isTurtleAhead() then
                if not turtle.forward() then
                    turtle.dig()
                else
                    break
                end
            end
            sleepForSeconds(1)
        end

        sleepForSeconds(3)

        -- Zurück ausweichen
        while true do
            if not isTurtleAhead() then
                if not turtle.back() then

                else
                    break
                end
            end
            sleepForSeconds(1)
        end
    else
        sleepForSeconds(1)
    end
end

local function up()
    while true do
        if isTurtleUp() then
            avoidTurtleByForward()

        elseif turtle.detectUp() then
            turtle.digUp()
        end

        if turtle.up() then
            break
        end
    end

    currentY = currentY + 1
    sendMessage()
    return true
end

local function down()
    while true do
        if isTurtleDown() then
            avoidTurtleByForward()

        elseif turtle.detectDown() then
            turtle.digDown()
        end

        if turtle.down() then
            break
        end
    end

    currentY = currentY - 1
    sendMessage()
    return true
end

local function forward()

    while true do
        if isTurtleAhead() then
            print("Turtle detected ahead, avoiding by Y axis")
            avoidTurtleByYAxis()

        elseif turtle.detect() then
            turtle.dig()
        end

        if turtle.forward() then
            break
        end
    end

    if direction == 1 then
        currentZ = currentZ - 1
    elseif direction == 2 then
        currentX = currentX + 1
    elseif direction == 3 then
        currentZ = currentZ + 1
    elseif direction == 4 then
        currentX = currentX - 1
    end
    sendMessage()
    return true
end

-- Richtungscode:
-- 1 = North, 2 = East, 3 = South, 4 = West

local function detectDirectionFromDelta(dx, dz)
    if math.abs(dx) > math.abs(dz) then
        return dx > 0 and 2 or 4 -- East / West
    elseif math.abs(dz) > math.abs(dx) then
        return dz > 0 and 3 or 1 -- South / North
    end
    return nil
end

-- Liefert stabilere GPS-Werte
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

    -- Zurück-Test
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

-- Bestimmt die Turtle-Richtung sicher
local function getDirection()
    local maxAttempts = 8
    for attempt = 1, maxAttempts do
        print("Attempting to detect direction... (attempt " .. attempt .. "/" .. maxAttempts .. ")")
        sendMessage()

        -- 1) forward
        local dir = testMovement(nil, nil)
        if dir then
            print("Direction detected: " .. directionToString(dir))
            return dir
        end

        -- 2) left
        dir = testMovement(function()
            turnLeft()
        end, function()
            turnRight()
        end)

        if dir then
            print("Direction detected (left): " .. directionToString(dir))
            return dir
        end

        -- 3) right
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

    -- Fallback: couldn't reliably detect direction. Use the current `direction` value (default set earlier)
    print("Warning: Could not detect direction after " .. maxAttempts ..
              " attempts. Falling back to current direction: " .. directionToString(direction))
    return direction
end

local function goToPosition(targetX, targetY, targetZ, targetDir)
    status = "Going to Position"
    print("Going to X:" .. targetX .. " Y:" .. targetY .. " Z:" .. targetZ .. " Dir:" .. directionToString(targetDir))

    ---------------------------------------------------------------------------
    -- 1. Y-Bewegung (hoch/runter)
    ---------------------------------------------------------------------------
    while currentY < targetY do
        up()
    end

    while currentY > targetY do
        down()
    end

    ---------------------------------------------------------------------------
    -- 2. X-Bewegung (Ost/West)
    ---------------------------------------------------------------------------
    if targetX > currentX then
        turnTo(2) -- East
        while currentX < targetX do
            forward()
        end
    elseif targetX < currentX then
        turnTo(4) -- West
        while currentX > targetX do
            forward()
        end
    end

    ---------------------------------------------------------------------------
    -- 3. Z-Bewegung (Nord/Süd)
    ---------------------------------------------------------------------------
    if targetZ > currentZ then
        turnTo(3) -- South
        while currentZ < targetZ do
            forward()
        end
    elseif targetZ < currentZ then
        turnTo(1) -- North
        while currentZ > targetZ do
            forward()
        end
    end

    ---------------------------------------------------------------------------
    -- 4. Endausrichtung
    ---------------------------------------------------------------------------
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
            log:logDebug("?", "chunkNumber " .. dataReceived.chunkNumber .. " assigned by Master")

            if os.getComputerLabel() == nil then
                log:logDebug(turtleName, "Setting computer label to " .. dataReceived.turtleName)
                os.setComputerLabel(dataReceived.turtleName)
                turtleName = dataReceived.turtleName
            end

            print("Going to chunk " .. dataReceived.chunkNumber)
            startCoords.x = dataReceived.chunkCoordinates.startX
            startCoords.z = dataReceived.chunkCoordinates.startZ
            startCoords.y = dataReceived.currentChunkDepth
            startCoords.direction = dataReceived.startDirection or 2

            chestCoords.x = dataReceived.chestCoordinates.x
            chestCoords.y = dataReceived.chestCoordinates.y
            chestCoords.z = dataReceived.chestCoordinates.z
            goToPosition(startCoords.x, startCoords.y, startCoords.z, startCoords.direction)
            break
        else
            log:logDebug(turtleName, "No response from Master, retrying in 3 seconds...")
            sleepForSeconds(3)
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
            -- testen, ob Item grundsätzlich als Fuel verwendbar ist
            if turtle.refuel(0) then
                -- kompletten Stack benutzen
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

local function mineStrip(length)
    for i = 1, length do
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
        turtle.digUp()
        turtle.digDown()
        forward()
        turtle.digUp()
        turtle.digDown()
    end
end

local function mineTripleLayer(length, width)
    for x = 1, length do
        mineStrip(width - 1) -- Minen der aktuellen Reihe

        if x < length then -- Nur drehen, wenn noch eine weitere Reihe folgt
            if x % 2 == 1 then
                turtle.digUp()
                turtle.digDown()
                turnRight()
                forward()
                turnRight()
                turtle.digUp()
                turtle.digDown()
            else
                turtle.digUp()
                turtle.digDown()
                turnLeft()
                forward()
                turnLeft()
                turtle.digUp()
                turtle.digDown()
            end
        end
    end

    -- Nach Beenden der Ebene zurück zum Start
    goToPosition(startCoords.x, currentY, startCoords.z, 2)
end

-- Main quarry function
local function quarry(length, width, height, startDirection)
    local layers = math.ceil(height / 3)

    for i = 1, layers do
        updateForComputer(currentY)
        mineTripleLayer(length, width)

        if i < layers then
            for d = 1, 3 do
                if currentY > -60 then
                    down()
                end
            end
        end
    end
end

-- Program Start
sleepForSeconds(3)

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

    while true do
        connectToMaster()
        sleepForSeconds(3)
        quarry(16, 16, startCoords.y, direction)
    end

else
    print("Could not determine initial position or direction. Aborting.")
end
