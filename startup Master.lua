local url = "https://api.github.com/repos/Seatrano/Minecraft_EasyMine/contents/Master.lua"

local headers = {
    ["User-Agent"] = "CC",
    ["Accept"] = "application/vnd.github.v3.raw"   -- WICHTIG: liefert echten Text, kein Base64
}

local response = http.get(url, headers)

if response then
    local content = response.readAll()
    response.close()

    local f = fs.open("Master.lua", "w")
    f.write(content)
    f.close()

    print("Master.lua erfolgreich aktualisiert.")
else
    print("Fehler: Datei konnte nicht geladen werden.")
end

shell.run("Master.lua")
