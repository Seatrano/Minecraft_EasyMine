local url = "https://api.github.com/repos/Seatrano/Minecraft_EasyMine/contents/Master.lua"

local headers = {
    ["User-Agent"] = "CC"    -- GitHub API verlangt einen User-Agent!
}

local response = http.get(url, headers)

if response then
    local json = response.readAll()
    response.close()

    local data = textutils.unserializeJSON(json)

    if not data or not data.content then
        print("Fehler: content nicht gefunden.")
        return
    end

    local decoded = textutils.decodeBase64(data.content)

    local f = fs.open("Master.lua", "w")
    f.write(decoded)
    f.close()

    print("Master.lua erfolgreich aktualisiert.")
else
    print("Fehler: Konnte die Datei nicht laden.")
end

shell.run("Master.lua")
