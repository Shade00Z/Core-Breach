-- ElevatorController
-- The elevator panel: opens from the elevator in any layer's plaza or the
-- headframe in Drill Town. Pick Drill Town or a layer you've unlocked; the
-- screen fades while the server moves you (HubService). Riding to another
-- layer is only a visit: your lane keeps playing your deepest layer.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local LayerConfig = require(Shared:WaitForChild("LayerConfig"))
local UIKit = require(script.Parent.Parent:WaitForChild("UIKit"))

local CLOSE_DISTANCE = 16

local ElevatorController = {}

local UIController
local SoundController
local panel: UIKit.Panel
local fade: Frame
local callPart: BasePart? = nil

local function travel(destination: number)
	panel.close()
	fade.Visible = true
	TweenService:Create(fade, TweenInfo.new(0.25), { BackgroundTransparency = 0 }):Play()
	SoundController:Play("RollStart")
	task.wait(0.3)
	Remotes.Event("ElevatorTravel"):FireServer(destination)
	task.wait(0.5)
	local tween = TweenService:Create(fade, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
	tween:Play()
	tween.Completed:Wait()
	fade.Visible = false -- hidden between rides, so it never sits over other buttons
end

local function refresh()
	UIKit.Clear(panel.body)
	local stats = UIController.Stats
	local unlocked = stats.layer or 1
	local here = stats.here or unlocked
	local function stop(order: number, destination: number, name: string, note: string)
		local row = UIKit.Row(panel.body, order, true)
		local label = UIKit.Label(row, name .. "\n" .. note, 16, nil, 1)
		label.Size = UDim2.new(1, -120, 0, 0)
		local isHere = destination == here
		local locked = destination > unlocked
		local text = if isHere then "You're here" elseif locked then "Locked" else "Go"
		local button = UIKit.Button(row, text, if isHere or locked then UIKit.Colors.Gray else UIKit.Colors.Green, UDim2.new(0, 110, 0, 40), function()
			if not isHere and not locked then
				task.spawn(travel, destination)
			end
		end)
		button.LayoutOrder = 2
		button.AutoButtonColor = not (isHere or locked)
	end
	stop(0, 0, "Drill Town", "The surface: leaderboards, the daily board, the Big Drill")
	for _, layer in LayerConfig.Layers do
		local note
		if layer.id > unlocked then
			local above = LayerConfig.Get(layer.id - 1)
			note = if above.boss then "Beat " .. above.boss.name .. " to break the seal" else "Coming soon"
		elseif layer.id == unlocked then
			note = "Your lane plays here"
		else
			note = "Visit: mine, forge and quests"
		end
		stop(layer.id, layer.id, string.format("Layer %d: %s", layer.id, layer.name), note)
	end
end

function ElevatorController:Init(controllers)
	UIController = controllers.UIController
	SoundController = controllers.SoundController
	local gui = UIController:GetGui()
	panel = UIKit.Panel(gui, "ElevatorPanel", "Elevator", 420, 330)

	fade = Instance.new("Frame")
	fade.Name = "ElevatorFade"
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BackgroundTransparency = 1
	fade.ZIndex = 50
	fade.Active = false
	fade.Visible = false
	fade.Parent = gui
end

function ElevatorController:Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "ElevatorPrompt" then
			callPart = prompt.Parent :: BasePart
			refresh()
			panel.open()
		end
	end)
	local lastKey = ""
	UIController.StatsUpdated:Connect(function(stats)
		local key = tostring(stats.layer) .. "/" .. tostring(stats.here)
		if key ~= lastKey then
			lastKey = key
			if panel.frame.Visible then
				refresh()
			end
		end
	end)
	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer += dt
		if timer < 0.3 or not panel.frame.Visible or not callPart then
			return
		end
		timer = 0
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or (root.Position - callPart.Position).Magnitude > CLOSE_DISTANCE then
			panel.close()
		end
	end)
end

return ElevatorController
