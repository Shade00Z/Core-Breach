-- Server entry point: starts every service in Services.
-- Each service may have :Init() (set up) and :Start() (connect events, begin
-- work). Init runs for all services first, then Start, in ORDER.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create all RemoteEvents before any client asks for them
require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Services = script:WaitForChild("Services")

local ORDER = {
	"DataService",
	"EconomyService",
	"CharacterService",
	"WaveService",
	"HubService",
	"TownService",
	"DailyService",
	"GearService",
	"DigService",
	"LootService",
	"MiningService",
	"BossService",
	"CrateService",
	"StoreService",
	"SettingsService",
	"ForgeService",
	"PowerService",
	"AbilityService",
	"QuestService",
	"DevService",
}

local loaded = {}
for _, name in ORDER do
	local module = Services:WaitForChild(name)
	loaded[name] = require(module)
end

for _, name in ORDER do
	local service = loaded[name]
	if type(service.Init) == "function" then
		service:Init(loaded)
	end
end

for _, name in ORDER do
	local service = loaded[name]
	if type(service.Start) == "function" then
		task.spawn(service.Start, service)
	end
end

print("[Core Breach] Server started")
