local url = "https://api.github.com/repos/Seatrano/Minecraft_EasyMine/contents/Master.lua"

local request = http.get(url, {
    ["User-Agent"] = "CC-HTTP"
})

if request then
    local data = textutils.unserializeJSON(request.readAll())
    request.close()

    local decoded = textutils.unserializeJSON(
        '{"content":"' .. data.content .. '","encoding":"base64"}'
    ).content

    local content = textutils.decode_base64(data.content)

    local f = fs.open("Master.lua", "w")
    f.write(content)
    f.close()

    print("Aktualisiert über GitHub API.")
else
    print("Fehler beim Laden über API.")
end

shell.run("Master.lua")
