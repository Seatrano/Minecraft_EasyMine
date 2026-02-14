-- Maximales Fuel-Level
local TARGET_FUEL = 100000

-- Tracking, wie viele Schritte wir vorwärts gelaufen sind
local steps = 0

-- Prüfe ob Bucket im Slot 1 ist
turtle.select(1)

if turtle.getFuelLevel() == "unlimited" then
    print("Unbegrenzter Fuel aktiviert – Skript nicht nötig.")
    return
end

-- Hauptschleife
while turtle.getFuelLevel() < TARGET_FUEL do
    -- Lava unter Turtle aufnehmen
    local success, err = turtle.placeDown()
    if not success then
        print("Fehler beim Aufnehmen der Lava: " .. (err or "unbekannt"))
        break
    end

    -- Refuel versuchen
    if not turtle.refuel() then
        print("Konnte nicht refuelen – kein Lava im Bucket?")
        break
    end

    -- Schritt vorwärts
    if turtle.forward() then
        steps = steps + 1
    else
        print("Kann nicht vorwärts gehen. Abbruch.")
        break
    end
end

print("Ziel erreicht oder Schleife beendet. Fuel-Level: " .. turtle.getFuelLevel())
print("Gehe nun zurück zum Startpunkt...")

-- Zurücklaufen
for i = 1, steps do
    turtle.back()
end

print("Wieder am Startpunkt.")
