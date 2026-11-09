-- Client entry point: starts every controller in Controllers.
-- Each controller may have :Init() (set up, no yielding on other controllers)
-- and :Start() (connect events, begin work). Init runs for all, then Start.

local Controllers = script:WaitForChild("Controllers")

local ORDER = {
	"SoundController",
	"EnemyRenderer",
	"FXController",
	"UIController",
	"CombatController",
	"CrateController",
	"GearController",
	"StatsController",
	"BagController",
	"ForgeController",
	"HubController",
	"BossController",
	"QuestController",
	"RebirthController",
	"OfflineController",
	"DevController",
}

local loaded = {}
for _, name in ORDER do
	local module = Controllers:WaitForChild(name)
	loaded[name] = require(module)
end

for _, name in ORDER do
	local controller = loaded[name]
	if type(controller.Init) == "function" then
		controller:Init(loaded)
	end
end

for _, name in ORDER do
	local controller = loaded[name]
	if type(controller.Start) == "function" then
		task.spawn(controller.Start, controller)
	end
end

print("[Core Breach] Client started")
