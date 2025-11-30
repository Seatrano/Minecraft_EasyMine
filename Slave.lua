local version = "1.4"
local trash = {
    ["minecraft:cobblestone"] = true,
    ["minecraft:dirt"] = true,
    ["minecraft:andesite"] = true,
    ["minecraft:diorite"] = true,
    ["create:limestone_cobblestone"] = true,
    ["minecraft:gravel"] = true,
    ["minecraft:granite"] = true
}

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

local chestCoords = {
    x = 528,
    y = 67,
    z = -80,
    direction = 2
}

local forward
local avoidOtherTurtle

local function sleepForSeconds(seconds)
    for i = 1, seconds do
        print("Sleeping... " .. (seconds - i + 1) .. "s remaining")
        os.sleep(1)
    end
end

local function liquidCheck()
    local success, data = turtle.inspect()

    if success and data and data.name == "minecraft:lava" and data.state and data.state.level == 0 then
        turtle.select(1)
        turtle.place()
        turtle.refuel(1)
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
    for i = 2, 16 do
        local item = turtle.getItemDetail(i)
        if item and trash[item.name] then
            turtle.select(i)
            turtle.dropDown()
        end
    end
end

local function sortInventory()
    -- 1) Stacks zusammenführen
    for i = 2, 16 do
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
    for i = 2, 16 do
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
    for i = 2, 16 do
        if turtle.getItemCount(i) == 0 then
            return false
        end
    end

    -- inventory ist voll -> sortieren und trash droppen
    sortInventory()
    dropTrash()

    for i = 2, 16 do
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

local function isTurtleBack()
    turtle.turnLeft()
    turtle.turnLeft()
    local success, data = turtle.inspect()
    turtle.turnLeft()
    turtle.turnLeft()
    return success and data and data.name == "computercraft:turtle_advanced"
end

local function updateForwardCoords(direction)
    if direction == 1 then
        currentZ = currentZ - 1
    elseif direction == 2 then
        currentX = currentX + 1
    elseif direction == 3 then
        currentZ = currentZ + 1
    elseif direction == 4 then
        currentX = currentX - 1
    end
end

forward = function()
    while isTurtleAhead() or turtle.detect() do
        if isTurtleAhead() then
            if avoidOtherTurtle() then
                break
            end
        else
            turtle.dig()
            liquidCheck()
        end
    end

    -- versuche vorwärts; falls fehlschlägt, wiederhole (robuster)
    while not turtle.forward() do
        -- falls etwas neues blockiert: dig/retry
        if isTurtleAhead() then
            if not avoidOtherTurtle() then
                -- wenn Ausweichen nicht möglich, kurz warten und weiter versuchen
                sleep(0.2)
            end
        else
            turtle.dig()
            liquidCheck()
        end
    end

    liquidCheck()
    updateForwardCoords(direction)
    sendMessage()
    return true
end

avoidOtherTurtle = function()

    while true do
        -- Zufällige Wartezeit zwischen 1 und 5 Sekunden
        local wait = math.random(1, 5)

        ------------------------------------------------------------------
        -- LINKS AUSWEICHEN
        ------------------------------------------------------------------
        turnLeft()
        if not isTurtleAhead() then
            if forward() then
                -- 180° drehen
                turnRight()
                turnRight()

                -- warten bis frei
                while isTurtleAhead() do
                    sleep(wait)
                end

                -- vorwärts bis erfolgreich
                while not forward() do
                    sleep(wait)
                end

                -- Richtung wiederherstellen
                turnLeft()
                return true
            end
        end

        -- Richtung korrigieren, falls forward() oben nicht ging
        turnRight()  


        ------------------------------------------------------------------
        -- RECHTS AUSWEICHEN
        ------------------------------------------------------------------
        turnRight()
        if not isTurtleAhead() then
            if forward() then
                -- 180° drehen
                turnLeft()
                turnLeft()

                -- warten bis frei
                while isTurtleAhead() do
                    sleep(wait)
                end

                -- vorwärts bis erfolgreich
                while not forward() do
                    sleep(wait)
                end

                -- Richtung wiederherstellen
                turnRight()
                return true
            end
        end

        -- Richtung korrigieren
        turnLeft()

        -- bevor der nächste Versuch beginnt → erneut zufällig warten
        sleep(wait)
    end
end


local function back()
    while isTurtleBack() or not turtle.back() do
        if isTurtleBack() then
            avoidOtherTurtle()
        else
            turtle.turnLeft()
            turtle.turnLeft()
            turtle.dig()
            turtle.turnLeft()
            turtle.turnLeft()
        end
    end

    if direction == 1 then
        currentZ = currentZ + 1
    elseif direction == 2 then
        currentX = currentX - 1
    elseif direction == 3 then
        currentZ = currentZ - 1
    elseif direction == 4 then
        currentX = currentX + 1
    end

    sendMessage()
    return true
end

local function up()
    while isTurtleUp() or not turtle.up() do
        if isTurtleUp() then
            avoidOtherTurtle()
        else
            turtle.digUp()
        end
    end

    currentY = currentY + 1
    sendMessage()
    return true
end

local function down()
    while isTurtleDown() or not turtle.down() do
        if isTurtleDown() then
            avoidOtherTurtle()
        else
            turtle.digDown()
        end
    end

    currentY = currentY - 1
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
    for i = 1, 5 do
        local x, y, z = gps.locate(1)
        if x and z then
            return x, y, z
        end
        os.sleep(0.2)
    end
    return nil
end

-- Führt eine Testbewegung aus und bestimmt die Richtung
local function testMovement(turnBefore, turnAfter, cx, cz)
    if turnBefore then
        turnBefore()
    end

    local x1, y1, z1 = stableGPS()
    print("testMovement: GPS before ->", x1, y1, z1)
    if not x1 then
        if turnAfter then
            turnAfter()
        end
        return nil
    end

    if not forward() then
        if turnAfter then
            turnAfter()
        end
        return nil
    end

    os.sleep(0.3) -- GPS-Sync
    local x2, y2, z2 = stableGPS()
    print("testMovement: GPS after  ->", x2, y2, z2)

    back()

    if turnAfter then
        turnAfter()
    end

    if not x2 then
        return nil
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
        local dir = testMovement(nil, nil, currentX, currentZ)
        if dir then
            print("Direction detected: " .. directionToString(dir))
            return dir
        end

        -- 2) left
        dir = testMovement(function()
            turnLeft()
        end, function()
            turnRight()
        end, currentX, currentZ)
        if dir then
            print("Direction detected (left): " .. directionToString(dir))
            return dir
        end

        -- 3) right
        dir = testMovement(function()
            turnRight()
        end, function()
            turnLeft()
        end, currentX, currentZ)
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
        up() -- nutzt Ausweichlogik
    end

    while currentY > targetY do
        down() -- nutzt Ausweichlogik
    end

    ---------------------------------------------------------------------------
    -- 2. X-Bewegung (Ost/West)
    ---------------------------------------------------------------------------
    if targetX > currentX then
        turnTo(2) -- East
        while currentX < targetX do
            forward() -- nutzt Ausweichlogik
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

    rednet.broadcast(textutils.serialize(data), "MT")
    while true do
        local id, msg = rednet.receive(turtleName)
        if msg then
            local parsed = textutils.unserialize(msg)
            print("Received message with msg:" .. msg)
            chunkNumber = parsed.chunkNumber
            print("Going to chunk " .. chunkNumber)

            startCoords.x = parsed.chunkCoordinates.startX
            startCoords.z = parsed.chunkCoordinates.startZ
            startCoords.y = parsed.currentChunkDepth
            startCoords.direction = parsed.startDirection or 2

            goToPosition(startCoords.x, startCoords.y, startCoords.z, startCoords.direction)
            break
        end
    end
end

local function refuel()
    status = "Refueling"
    sendMessage()

    for slot = 2, 16 do
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
    for i = 2, 16 do
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

local function turtleIsReady()
    local slot = 1
    local detail = turtle.getItemDetail(slot)
    if detail and detail.name == "minecraft:bucket" and detail.count == 1 then
        return true
    else
        print("Please place a single bucket in slot 1 for refueling.")
        goToPosition(chestCoords.x, chestCoords.y, chestCoords.z, chestCoords.direction)
        return false
    end
end

-- Program Start
print("Miner Turtle Version " .. version)
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

local sides = {"top", "bottom", "left", "right", "front", "back"}
local modemSide = nil
for _, side in ipairs(sides) do
    if peripheral.getType(side) == "modem" then
        modemSide = side
        break
    end
end

if modemSide then
    rednet.open(modemSide)
end

direction = getDirection()
if currentX and currentY and currentZ and direction then

    print("Starting at X:" .. currentX .. " Y:" .. currentY .. " Z:" .. currentZ,
        "facing direction:" .. directionToString(direction))

    while true do
        if not turtleIsReady() then
            sendMessage()
            print("Turtle not ready. Retrying in 10 seconds...")
            sleepForSeconds(10)
            break
        end
        connectToMaster()
        sleepForSeconds(3)
        quarry(16, 16, startCoords.y, direction)
    end

else
    print("Could not determine initial position or direction. Aborting.")
end
