-- Roblox Lua Script

-- This script does something interesting in Roblox

local function greetPlayer(player)
    print("Welcome to the game, " .. player.Name ..!")
end

-- Event listener for player joining
game.Players.PlayerAdded:Connect(greetPlayer)