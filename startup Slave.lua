local apiBase = "https://api.github.com/repos/Seatrano/Minecraft_EasyMine/contents/"

local headers = {
    ["User-Agent"] = "CC",
    ["Accept"] = "application/vnd.github.v3.raw"
}

local function downloadFile(path)
    local url = apiBase .. path
    local response = http.get(url, headers)

    if not response then
        print("ERROR downloading " .. path)
        return
    end

    local content = response.readAll()
    response.close()

    -- Ensure folder exists
    local folder = fs.getDir(path)
    if not fs.exists(folder) then
        fs.makeDir(folder)
    end

    local f = fs.open(path, "w")
    f.write(content)
    f.close()

    print("Updated: " .. path)
end

local function updateHelpers()
    local url = apiBase .. "helper"
    local response = http.get(url, { ["User-Agent"] = "CC" })

    if not response then
        print("ERROR: could not list helper folder")
        return
    end

    local files = textutils.unserializeJSON(response.readAll())
    response.close()

    for _, file in ipairs(files) do
        if file.type == "file" then
            downloadFile("helper/" .. file.name)
        end
    end
end

downloadFile("Slave.lua")
updateHelpers()
shell.run("Slave.lua")