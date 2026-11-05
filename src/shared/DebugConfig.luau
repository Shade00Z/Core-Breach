-- DebugConfig
-- Testing switches. They ALWAYS work in Roblox Studio playtests.
-- In the published game they are ignored, unless AllowInLiveGame is true,
-- and even then they only apply to the game's creator (for phone testing).
--
-- Before release: set AllowInLiveGame back to false.

local RunService = game:GetService("RunService")

export type Settings = {
	StartWave: number,
	InvincibleBarricade: boolean,
	EnemyCountOverride: number,
}

local SETTINGS: Settings = {
	StartWave = 1, -- start every lane on this wave (try 19 to see the first boss)
	InvincibleBarricade = false, -- the barricade never breaks, so waves keep coming with no gear
	EnemyCountOverride = 0, -- force this many enemies per wave (150 for the phone stress test). 0 = normal
}

local AllowInLiveGame = false -- set true to use these settings on your phone (creator only)

local DEFAULTS: Settings = {
	StartWave = 1,
	InvincibleBarricade = false,
	EnemyCountOverride = 0,
}

local DebugConfig = {}

local function isCreator(player: Player): boolean
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

-- Is debug mode on for this player?
function DebugConfig.IsActive(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return AllowInLiveGame and isCreator(player)
end

-- The settings that apply to this player (defaults when debug is off).
function DebugConfig.For(player: Player): Settings
	return if DebugConfig.IsActive(player) then SETTINGS else DEFAULTS
end

-- True if any setting differs from normal play (used to show a DEBUG label).
function DebugConfig.Changes(settings: Settings): boolean
	return settings.StartWave ~= DEFAULTS.StartWave
		or settings.InvincibleBarricade ~= DEFAULTS.InvincibleBarricade
		or settings.EnemyCountOverride ~= DEFAULTS.EnemyCountOverride
end

return DebugConfig
