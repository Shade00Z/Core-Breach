-- SettingsService
-- Saves each player's settings (sound and music volume, low graphics,
-- effects) so they're the same next time and on other devices. The settings
-- only change what that player's own screen and speakers do; the client
-- applies them (SettingsController, ClientSettings).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local SettingsService = {}

local services

local function push(player: Player)
	services.EconomyService:PushStats(player, { settings = table.clone(services.DataService:Get(player).settings) })
end

local function onSave(player: Player, key: unknown, value: unknown)
	if not services.DataService:IsLoaded(player) then
		return
	end
	local settings = services.DataService:Get(player).settings
	if (key == "sound" or key == "music") and type(value) == "number" and value == value then
		settings[key] = math.clamp(value, 0, 1)
	elseif (key == "lowGraphics" or key == "effects") and type(value) == "boolean" then
		settings[key] = value
	end
end

function SettingsService:Init(allServices)
	services = allServices
end

function SettingsService:Start()
	Remotes.Event("SaveSetting").OnServerEvent:Connect(onSave)
	services.DataService.Loaded:Connect(push)
	for _, player in Players:GetPlayers() do
		if services.DataService:IsLoaded(player) then
			push(player)
		end
	end
end

return SettingsService
