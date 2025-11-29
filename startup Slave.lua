-- startup.lua
local url = "https://raw.githubusercontent.com/Seatrano/Minecraft_EasyMine/main/Slave.lua?ts=" .. os.epoch("utc")
local fileName = "Slave.lua"  -- die Datei, die ausgeführt wird

-- Versuche, die aktuelle Datei von GitHub zu laden
if http then
    local response = http.get(url)
    if response then
        local content = response.readAll()
        response.close()
        -- Überschreibe die aktuelle startup Datei
        local f = fs.open(fileName, "w")
        f.write(content)
        f.close()
        print("Startup erfolgreich aktualisiert.")
    else
        print("Fehler: Konnte die Datei nicht herunterladen.")
    end
else
    print("HTTP API ist deaktiviert! Setze 'enable_http' in den CC-Einstellungen.")
end

-- Starte die Datei
if fs.exists(fileName) then
    shell.run(fileName)
else
    print("Fehler: Startup-Datei nicht gefunden.")
end
