local players = game:GetService("Players")
local tws = game:GetService("TweenService")
local ts = game:GetService("TeleportService")

local plr = players.LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")
local hum = char:WaitForChild("Humanoid")

local drops_path = workspace:WaitForChild("Drops")
local finger_queue = {}
local collecting = false
local waiting_for_finger = false

-- Carrega servidores visitados de sessão anterior
local visited_servers = _G.visited_servers or {}
visited_servers[game.JobId] = true
_G.visited_servers = visited_servers

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
    local time_ = math.clamp(magnitude / 200, 0.01, 15)
    if typeof(pos) == "Vector3" then pos = CFrame.new(pos) end
    local tween = tws:Create(hrp, TweenInfo.new(time_), {CFrame = pos})
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

local function trocar_servidor()
    print("Procurando novo servidor...")
    local placeId = game.PlaceId
    local cursor = nil
    local tentativas = 0

    repeat
        tentativas += 1
        local ok, result = pcall(function()
            return ts:GetSortedGameInstances(placeId, 20, cursor)
        end)

        if not ok or not result then
            task.wait(3)
            break
        end

        for _, server in ipairs(result.Instances) do
            -- checagem extra: não entrar no mesmo JobId atual
            if server.Id ~= game.JobId and not visited_servers[server.Id] and server.Playing < server.MaxPlayers then
                visited_servers[server.Id] = true
                _G.visited_servers = visited_servers
                print("Entrando em servidor:", server.Id)
                ts:TeleportToPlaceInstance(placeId, server.Id, plr)
                return
            end
        end

        cursor = result.NextPageCursor
    until cursor == nil or tentativas >= 5

    -- Sem servidores novos, reseta lista
    print("Sem servidores novos, resetando lista...")
    _G.visited_servers = {}
    _G.visited_servers[game.JobId] = true
    ts:Teleport(placeId, plr)
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
    print("Fila vazia! Aguardando novos dedos por 5 segundos antes de trocar servidor...")

    -- Aguarda 5 segundos por novos dedos antes de trocar
    waiting_for_finger = true
    local t = 0
    while t < 5 do
        task.wait(1)
        t += 1
        if not waiting_for_finger then
            -- Novo dedo apareceu, cancela o timer
            return
        end
    end

    -- 5 segundos sem dedo, troca servidor
    print("5 segundos sem dedo, trocando servidor...")
    trocar_servidor()
end

-- Dedos já existentes ao iniciar
for _, v in pairs(drops_path:GetChildren()) do
    if v.Name == "CursedFinger" then
        table.insert(finger_queue, v)
        print("Dedo existente detectado!")
    end
end

-- Detecta novos dedos em tempo real
drops_path.ChildAdded:Connect(function(child)
    if child.Name == "CursedFinger" then
        print("Novo dedo detectado!")
        table.insert(finger_queue, child)
        if waiting_for_finger then
            -- Cancela o timer e vai coletar
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
    -- Sem dedos ao iniciar, espera 5s antes de trocar
    print("Nenhum dedo no servidor, aguardando 5 segundos...")
    waiting_for_finger = true
    task.spawn(function()
        local t = 0
        while t < 5 do
            task.wait(1)
            t += 1
            if not waiting_for_finger then return end
        end
        print("5 segundos sem dedo, trocando servidor...")
        trocar_servidor()
    end)
end

print("Auto Fingers iniciado! Servidor:", game.JobId)
