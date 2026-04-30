local player = game.Players.LocalPlayer
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local placeId = game.PlaceId

-- Lista das posições centrais das ilhas
local islandCenters = {
    Vector3.new(155.707275390625, 911.93701171875, 2838.251953125),
    Vector3.new(-66.57591247558594, 197.21002197265625, 452.09735107421875),
    Vector3.new(4131.4423828125, 86.53740692138672, 5892.42626953125),
    Vector3.new(-2903.63134765625, 208.41400146484375, 7126.85986328125),
    Vector3.new(80.08580017089844, 223.35675048828125, 8428.873046875),
    Vector3.new(-1946.633056640625, 169.32435607910156, 4541.62109375),
    Vector3.new(4166.26025390625, 22.594202041625977, 160.32601928710938),
}

-- Função de server hop aleatório
local function serverHop()
    local success, result = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(
            "https://games.roblox.com/v1/games/"..placeId.."/servers/Public?sortOrder=Asc&limit=100"
        ))
    end)
    if success and result and result.data then
        local servers = {}
        for _, server in pairs(result.data) do
            if server.playing < server.maxPlayers and server.id ~= game.JobId then
                table.insert(servers, server)
            end
        end
        if #servers > 0 then
            local randomServer = servers[math.random(1, #servers)]
            TeleportService:TeleportToPlaceInstance(placeId, randomServer.id, player)
        else
            warn("Nenhum servidor válido encontrado para hop.")
        end
    end
end

local function inject()
    local character = player.Character or player.CharacterAdded:Wait()
    local fingers = {}
    local scanningIslands = true

    local function addFinger(obj)
        local part = obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")) or obj
        if part and part:IsA("BasePart") then
            if not table.find(fingers, part) then
                table.insert(fingers, part)
                scanningIslands = false -- achou dedo, para voo
            end
        end
    end

    local function removeFinger(obj)
        for i, part in ipairs(fingers) do
            if part == obj or (obj:IsA("Model") and part:IsDescendantOf(obj)) then
                table.remove(fingers, i)
                break
            end
        end
        if #fingers == 0 then
            scanningIslands = true
            task.spawn(islandScanLoop)
        end
    end

    local function scanDrops()
        for _, child in pairs(workspace.Drops:GetChildren()) do
            local finger = child:FindFirstChild("CursedFinger")
            if finger then
                addFinger(finger)
            end
        end
    end

    local function watchDrops()
        fingers = {}
        scanDrops()

        workspace.Drops.ChildAdded:Connect(function(newChild)
            local finger = newChild:FindFirstChild("CursedFinger")
            if finger then
                addFinger(finger)
            end
        end)

        workspace.Drops.ChildRemoved:Connect(function(oldChild)
            local finger = oldChild:FindFirstChild("CursedFinger")
            if finger then
                removeFinger(finger)
            end
        end)
    end

    -- voo ajustado (um pouco mais lento e suave)
    local function flyTo(targetPos)
        if not character or not character.PrimaryPart then return end
        local startPos = character.PrimaryPart.Position
        local steps = 40 -- mais passos
        for i = 1, steps do
            if not scanningIslands then break end
            local alpha = i / steps
            local newPos = startPos:Lerp(targetPos, alpha)
            character:SetPrimaryPartCFrame(CFrame.new(newPos))
            task.wait(0.15) -- mais lento que antes
        end
    end

    function islandScanLoop()
        task.spawn(function()
            local found = false
            while scanningIslands do
                for _, pos in ipairs(islandCenters) do
                    if not scanningIslands then break end
                    flyTo(pos)
                    task.wait(2) -- espera maior entre ilhas
                    scanDrops()
                    if #fingers > 0 then
                        found = true
                        break
                    end
                end
                if not found then
                    serverHop() -- troca de servidor se não achou dedo
                end
            end
        end)
    end

    local function getNearestFinger()
        if not character or not character.PrimaryPart then return nil end
        local nearest, dist = nil, math.huge
        for _, part in ipairs(fingers) do
            local d = (part.Position - character.PrimaryPart.Position).Magnitude
            if d < dist then
                dist = d
                nearest = part
            end
        end
        return nearest
    end

    local function teleportLoop()
        while true do
            local nearest = getNearestFinger()
            if nearest then
                character:SetPrimaryPartCFrame(CFrame.new(nearest.Position))
            end
            task.wait(1)
        end
    end

    watchDrops()
    task.spawn(islandScanLoop)
    task.spawn(teleportLoop)
end

inject()

player.CharacterAdded:Connect(function()
    inject()
end)
