if not game:IsLoaded() then
    game.Loaded:Wait()
end

local players = game:GetService("Players")
local tws = game:GetService("TweenService")
local ts = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local plr = players.LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")
local hum = char:WaitForChild("Humanoid")

local drops_path = workspace:WaitForChild("Drops")
local finger_queue = {}
local collecting = false
local waiting_for_finger = false

-- =========================
-- 🔥 MEMÓRIA ENTRE SERVIDORES
-- =========================
getgenv().VisitedServers = getgenv().VisitedServers or {}
local servidores_visitados = getgenv().VisitedServers

local function save_memory()
    if queue_on_teleport then
        queue_on_teleport("getgenv().VisitedServers = " .. HttpService:JSONEncode(servidores_visitados))
    elseif syn and syn.queue_on_teleport then
        syn.queue_on_teleport("getgenv().VisitedServers = " .. HttpService:JSONEncode(servidores_visitados))
    end
end

local function character_available()
    local available = false
    char = plr.Character
    if not char then return available end
    hrp = char:FindFirstChild("HumanoidRootPart")
    hum = char:FindFirstChildOfClass("Humanoid")
    local ingame_hp = char:FindFirstChild("Health")
    if not ingame_hp or ingame_hp.Value <= 0 then return available end
    if hrp and hum then available = true end
    return available
end

local function go_to_pos_wait(pos, magnitude)
    if not character_available() then return end
    
    -- ⚡ um pouco mais rápido (seguro)
    local time_ = math.clamp(magnitude / 85, 0.2, 25)
    
    if typeof(pos) == "Vector3" then pos = CFrame.new(pos) end
    local tween = tws:Create(hrp, TweenInfo.new(time_, Enum.EasingStyle.Linear), {CFrame = pos})
    tween:Play()
    tween.Completed:Wait()
    if hrp then hrp.Anchored = false end
end

local function get_finger_pos(finger)
    local x = finger:FindFirstChild("x")
    local y = finger:FindFirstChild("y")
    local z = finger:FindFirstChild("z")
    if x and y and z then
        return Vector3.new(x.Value, y.Value, z.Value)
    end
    local part = finger:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

-- =========================
-- 🔥 SERVER HOP INTELIGENTE
-- =========================
local function trocar_servidor()
    local placeId = game.PlaceId
    local cursor = ""
    local achou = false

    print("Buscando servidores...")

    for i = 1, 5 do
        local url = "https://games.roblox.com/v1/games/"..placeId.."/servers/Public?sortOrder=Asc&limit=100&cursor="..cursor

        local ok, res = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(url))
        end)

        if ok and res and res.data then
            for _, server in ipairs(res.data) do
                if server.playing >= 5 and server.playing < server.maxPlayers and server.id ~= game.JobId then
                    if not servidores_visitados[server.id] then
                        servidores_visitados[server.id] = true
                        save_memory()

                        print("Entrando em servidor novo:", server.id)

                        task.wait(1)
                        ts:TeleportToPlaceInstance(placeId, server.id, plr)
                        achou = true
                        return
                    end
                end
            end

            cursor = res.nextPageCursor or ""
        else
            warn("Erro ao buscar servidores")
            break
        end
    end

    -- fallback inteligente (NÃO reseta memória fácil)
    if not achou then
        print("Nenhum servidor novo... tentando fallback")

        local url = "https://games.roblox.com/v1/games/"..placeId.."/servers/Public?sortOrder=Desc&limit=100"

        local ok, res = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(url))
        end)

        if ok and res and res.data then
            for _, server in ipairs(res.data) do
                if server.playing > 5 and server.id ~= game.JobId then
                    print("Fallback entrando:", server.id)

                    servidores_visitados[server.id] = true
                    save_memory()

                    task.wait(1)
                    ts:TeleportToPlaceInstance(placeId, server.id, plr)
                    return
                end
            end
        end

        print("Nada encontrado... aguardando antes de tentar novamente")
        task.wait(15)
        trocar_servidor()
    end
end

local function process_queue()
    if collecting then return end
    collecting = true
    waiting_for_finger = false

    while #finger_queue > 0 do
        if not character_available() then task.wait(1) continue end

        local nearest, nearestPos, shortest = nil, nil, math.huge
        for i, finger in ipairs(finger_queue) do
            if not finger or not finger.Parent then
                table.remove(finger_queue, i)
                continue
            end
            local pos = get_finger_pos(finger)
            if pos then
                local dist = (hrp.Position - pos).Magnitude
                if dist < shortest then
                    shortest = dist
                    nearest = finger
                    nearestPos = pos
                end
            end
        end

        if not nearest then break end

        print("Indo para dedo, distancia:", math.floor(shortest))

        while nearest and nearest.Parent and nearest:IsDescendantOf(drops_path) do
            if not character_available() then task.wait(1) break end
            local pos = get_finger_pos(nearest)
            if not pos then break end
            go_to_pos_wait(pos, (hrp.Position - pos).Magnitude)
            task.wait(0.3)
        end

        local idx = table.find(finger_queue, nearest)
        if idx then table.remove(finger_queue, idx) end

        print("Dedo coletado!")
    end

    collecting = false
    print("Fila vazia! Aguardando mais tempo antes de trocar servidor...")

    waiting_for_finger = true
    local t = 0
    while t < 20 do -- ⬅️ aumentado
        task.wait(1)
        t += 1
        if not waiting_for_finger then return end
    end

    if waiting_for_finger then
        print("Servidor realmente vazio, trocando...")
        trocar_servidor()
    end
end

-- resto do script (INALTERADO)
for _, v in pairs(drops_path:GetChildren()) do
    if v.Name == "CursedFinger" then
        table.insert(finger_queue, v)
        print("Dedo existente detectado!")
    end
end

drops_path.ChildAdded:Connect(function(child)
    if child.Name == "CursedFinger" then
        print("Novo dedo detectado!")
        table.insert(finger_queue, child)
        if waiting_for_finger then
            waiting_for_finger = false
            task.spawn(process_queue)
        elseif not collecting then
            task.spawn(process_queue)
        end
    end
end)

if #finger_queue > 0 then
    task.spawn(process_queue)
else
    print("Nenhum dedo no servidor, aguardando...")
    waiting_for_finger = true
    task.spawn(function()
        local t = 0
        while t < 20 do
            task.wait(1)
            t += 1
            if not waiting_for_finger then return end
        end
        if waiting_for_finger then
            trocar_servidor()
        end
    end)
end

print("Auto Fingers iniciado! Servidor:", game.JobId)
