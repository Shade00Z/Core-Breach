-- ReDrillController
-- The Re-Drill panel, opened at the Big Drill in Drill Town (server:
-- EconomyService:ReDrill). Shows what you need, what resets, what you keep
-- and what you gain. The button needs two clicks, so it's never pressed by
-- accident.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = require(Shared:WaitForChild("ProgressionConfig"))
local UIKit = require(script.Parent.Parent:WaitForChild("UIKit"))

local CLOSE_DISTANCE = 20

local ReDrillController = {}

local UIController
local SoundController
local panel: UIKit.Panel
local drillPart: BasePart? = nil
local armedUntil = 0

local function refresh()
	if not panel.frame.Visible then
		return
	end
	local stats = UIController.Stats
	local reDrills = stats.reDrills or 0
	local rebirths = stats.rebirths or 0
	local needed = stats.reDrillNeeds or Config.ReDrill.RebirthsNeeded
	local ready = rebirths >= needed
	local C = UIKit.Colors
	UIKit.Clear(panel.body)

	UIKit.Label(panel.body, string.format("Re-Drill %d", reDrills + 1), 20, C.Gold, 1)
	UIKit.Label(panel.body, string.format("Needs %d rebirths. You have %d.", needed, rebirths), 16, if ready then Color3.fromRGB(150, 255, 170) else Color3.fromRGB(255, 150, 150), 2)
	UIKit.Label(panel.body, string.format("GAIN (for good):  gear damage x%.1f (total x%.2f),  luck +%d%%", Config.ReDrill.DPSMult, Config.ReDrill.DPSMult ^ (reDrills + 1), math.floor(Config.ReDrill.LuckBonus * 100 + 0.5)), 15, Color3.fromRGB(150, 255, 170), 3)
	UIKit.Label(panel.body, string.format("RESET:  your rebirths (coin bonus x%.2f back to x1), your wave (back to 1) and your layer (back to Layer 1: beat Rootmaw again to go down).", stats.coinMultiplier or 1), 15, Color3.fromRGB(255, 190, 150), 4)
	UIKit.Label(panel.body, "KEEP:  coins, every gear and its level and forging, opened wall slots, loot, your hero's level and stats, quests and the Gear Index.", 15, nil, 5)

	local button
	button = UIKit.Button(panel.body, if ready then "RE-DRILL" else "Not yet", if ready then Color3.fromRGB(210, 110, 40) else C.Gray, UDim2.new(1, 0, 0, 46), function()
		if not ready then
			return
		end
		if os.clock() < armedUntil then
			armedUntil = 0
			Remotes.Event("RequestReDrill"):FireServer()
			SoundController:Play("Rebirth")
			panel.close()
			return
		end
		armedUntil = os.clock() + 3
		button.Text = "Sure? Click again to Re-Drill"
		button.BackgroundColor3 = C.Red
	end)
	button.LayoutOrder = 6
	button.TextSize = 20
end

function ReDrillController:Init(controllers)
	UIController = controllers.UIController
	SoundController = controllers.SoundController
	panel = UIKit.Panel(UIController:GetGui(), "ReDrillPanel", "The Big Drill", 480, 400)
end

function ReDrillController:Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "ReDrillPrompt" then
			drillPart = prompt.Parent :: BasePart
			armedUntil = 0
			panel.open()
			refresh()
		end
	end)
	local lastKey = ""
	UIController.StatsUpdated:Connect(function(stats)
		local key = tostring(stats.rebirths) .. "/" .. tostring(stats.reDrills)
		if key ~= lastKey then
			lastKey = key
			refresh()
		end
	end)
	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer += dt
		if timer < 0.3 or not panel.frame.Visible or not drillPart then
			return
		end
		timer = 0
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or (root.Position - drillPart.Position).Magnitude > CLOSE_DISTANCE then
			panel.close()
		end
	end)
end

return ReDrillController
