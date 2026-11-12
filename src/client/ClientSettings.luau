-- ClientSettings
-- This player's settings and screen mode, shared by every controller.
--   ClientSettings.Get("effects")      read a setting
--   ClientSettings.Set("effects", v)   change it (SettingsController does this)
--   ClientSettings.Changed             fires (key, value) after any change
-- Settings (saved by the server, SettingsService):
--   sound        0-1  sound effects volume
--   music        0-1  music volume (music arrives with the week 10 sound pass)
--   lowGraphics  fewer tracers, no muzzle flashes, no shadows or effect lights
--   effects      tracers, muzzle flashes, kill pops and damage numbers on/off
-- Also: compact = true on phones and small screens (MobileController sets it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Signal"))

local ClientSettings = {}

ClientSettings.Defaults = { sound = 1, music = 1, lowGraphics = false, effects = true }
ClientSettings.Changed = Signal.new()

local values: { [string]: any } = table.clone(ClientSettings.Defaults)

function ClientSettings.Get(key: string): any
	return values[key]
end

function ClientSettings.Set(key: string, value: any)
	if values[key] ~= value then
		values[key] = value
		ClientSettings.Changed:Fire(key, value)
	end
end

return ClientSettings
