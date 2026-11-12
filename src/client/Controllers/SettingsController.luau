-- SettingsController
-- The Settings screen (HUD button "Settings"): sound and music volume, low
-- graphics and effects. Changes apply at once (ClientSettings tells the other
-- controllers) and are saved by the server (SettingsService).
--   * Volumes set the "Effects" and "Music" sound groups.
--   * Low graphics also turns shadows off.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local UIKit = require(script.Parent.Parent:WaitForChild("UIKit"))
local ClientSettings = require(script.Parent.Parent:WaitForChild("ClientSettings"))

local VOLUME_STEP = 0.25

local SettingsController = {}

local UIController
local saveRemote: RemoteEvent
local panel: UIKit.Panel
local shadowsDefault = Lighting.GlobalShadows

local function soundGroup(name: string): SoundGroup
	local group = SoundService:FindFirstChild(name)
	if not group or not group:IsA("SoundGroup") then
		group = Instance.new("SoundGroup")
		group.Name = name
		group.Parent = SoundService
	end
	return group :: SoundGroup
end

local function apply()
	soundGroup("Effects").Volume = ClientSettings.Get("sound")
	soundGroup("Music").Volume = ClientSettings.Get("music")
	Lighting.GlobalShadows = shadowsDefault and not ClientSettings.Get("lowGraphics")
end

local function change(key: string, value: any)
	ClientSettings.Set(key, value)
	saveRemote:FireServer(key, value)
	apply()
end

local function build()
	UIKit.Clear(panel.body)
	local C = UIKit.Colors

	local function row(order: number, title: string, note: string): Frame
		local frame = UIKit.Row(panel.body, order)
		local header = Instance.new("Frame")
		header.BackgroundTransparency = 1
		header.Size = UDim2.new(1, 0, 0, 40)
		header.Parent = frame
		local name = UIKit.Label(header, title, 18)
		name.Size = UDim2.new(1, -200, 1, 0)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.TextYAlignment = Enum.TextYAlignment.Center
		UIKit.Label(frame, note, 13, C.Dim)
		return header
	end

	local function volumeRow(order: number, key: string, title: string, note: string)
		local header = row(order, title, note)
		local value = ClientSettings.Get(key)
		local minus = UIKit.Button(header, "-", C.Gray, UDim2.new(0, 48, 0, 38), function()
			change(key, math.max(0, value - VOLUME_STEP))
			build()
		end)
		minus.Position = UDim2.new(1, -184, 0, 1)
		local shown = UIKit.Label(header, if value <= 0 then "Off" else string.format("%d%%", value * 100), 17)
		shown.Size = UDim2.new(0, 76, 1, 0)
		shown.Position = UDim2.new(1, -130, 0, 0)
		shown.AutomaticSize = Enum.AutomaticSize.None
		shown.TextXAlignment = Enum.TextXAlignment.Center
		shown.TextYAlignment = Enum.TextYAlignment.Center
		local plus = UIKit.Button(header, "+", C.Gray, UDim2.new(0, 48, 0, 38), function()
			change(key, math.min(1, value + VOLUME_STEP))
			build()
		end)
		plus.Position = UDim2.new(1, -48, 0, 1)
	end

	local function switchRow(order: number, key: string, title: string, note: string)
		local header = row(order, title, note)
		local on = ClientSettings.Get(key) == true
		local b = UIKit.Button(header, if on then "On" else "Off", if on then C.Green else C.Gray, UDim2.new(0, 90, 0, 38), function()
			change(key, not on)
			build()
		end)
		b.Position = UDim2.new(1, -90, 0, 1)
	end

	volumeRow(1, "sound", "Sound effects", "Shots, hits, coins and rolls.")
	volumeRow(2, "music", "Music", "Hub and layer music.")
	switchRow(3, "lowGraphics", "Low graphics", "Fewer tracers, no muzzle flashes, no shadows. Turn on if the game stutters.")
	switchRow(4, "effects", "Combat effects", "Tracers, muzzle flashes, kill pops and damage numbers.")
end

function SettingsController:Init(controllers)
	UIController = controllers.UIController
	local gui = UIController:GetGui()
	panel = UIKit.Panel(gui, "SettingsPanel", "Settings", 480, 380)
	local toggle = UIKit.HudButton(gui, "Settings", Color3.fromRGB(80, 82, 96), UDim2.new(0, 12, 0.5, 166))
	toggle.Size = UDim2.new(0, 188, 0, 32)
	toggle.TextSize = 16
	toggle.Activated:Connect(function()
		if panel.frame.Visible then
			panel.close()
		else
			panel.open()
			build()
		end
	end)
end

function SettingsController:Start()
	saveRemote = Remotes.Event("SaveSetting")
	apply()
	-- Saved settings arrive once, when your save loads
	local loaded = false
	UIController.StatsUpdated:Connect(function(stats)
		if loaded or type(stats.settings) ~= "table" then
			return
		end
		loaded = true
		for key, default in ClientSettings.Defaults do
			local saved = stats.settings[key]
			if type(saved) == type(default) then
				ClientSettings.Set(key, saved)
			end
		end
		apply()
		if panel.frame.Visible then
			build()
		end
	end)
end

return SettingsController
