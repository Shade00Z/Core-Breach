-- SoundController
-- Plays the sound effects listed in shared/SoundConfig.
--   SoundController:Play("RollStart")             plain sound, same volume everywhere
--   SoundController:PlayAt("Shot", gun.Position)  comes from that spot in the world,
--                                                 quieter the further away you are
-- Each sound has a few copies so it can overlap with itself, and a per-second
-- limit so fast guns don't become a wall of noise. Sounds with a range in
-- SoundConfig are 3D: full volume up to range[1] studs, silent at range[2].

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SoundConfig"))

type Entry = {
	info: SoundConfig.SoundInfo,
	copies: { Sound },
	next: number,
	recent: { number }, -- times of recent plays, for the per-second limit
}

local SoundController = {}

local entries: { [string]: Entry } = {}
local rng = Random.new()

local function makeSound(name: string, info: SoundConfig.SoundInfo, parent: Instance): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. info.id
	sound.Volume = info.volume
	if info.range then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = info.range[1]
		sound.RollOffMaxDistance = info.range[2]
	end
	sound.Parent = parent
	return sound
end

function SoundController:Init()
	local folder = Instance.new("Folder")
	folder.Name = "GameSounds"
	folder.Parent = SoundService

	for name, info in SoundConfig.Sounds do
		local copies = {}
		for i = 1, info.voices or 1 do
			if info.range then
				-- A 3D sound needs a place in the world: an attachment we move before each play
				local attachment = Instance.new("Attachment")
				attachment.Name = "Sound_" .. name .. i
				attachment.Parent = workspace.Terrain
				table.insert(copies, makeSound(name .. i, info, attachment))
			else
				table.insert(copies, makeSound(name .. i, info, folder))
			end
		end
		entries[name] = { info = info, copies = copies, next = 1, recent = {} }
	end
end

-- True if the per-second limit allows another play right now
local function allowed(entry: Entry): boolean
	local limit = entry.info.maxPerSecond
	if not limit then
		return true
	end
	local now = os.clock()
	local recent = entry.recent
	while #recent > 0 and now - recent[1] > 1 do
		table.remove(recent, 1)
	end
	if #recent >= limit then
		return false
	end
	table.insert(recent, now)
	return true
end

local function play(entry: Entry, position: Vector3?): boolean
	local info = entry.info
	if position and info.range then
		-- Too far away to hear: skip it so it doesn't use up the rate limit
		local camera = workspace.CurrentCamera
		if camera and (camera.CFrame.Position - position).Magnitude > info.range[2] then
			return false
		end
	end
	if not allowed(entry) then
		return false
	end

	local sound = entry.copies[entry.next]
	entry.next = entry.next % #entry.copies + 1
	if position then
		local attachment = sound.Parent
		if attachment and attachment:IsA("Attachment") then
			attachment.WorldPosition = position
		end
	end
	if info.pitch then
		sound.PlaybackSpeed = rng:NextNumber(info.pitch[1], info.pitch[2])
	end
	sound.TimePosition = 0
	sound:Play()
	return true
end

-- Plays a sound by name. Returns false if it was skipped by the rate limit.
-- A 3D sound played this way comes from wherever it last played.
function SoundController:Play(name: string): boolean
	local entry = entries[name]
	return if entry then play(entry, nil) else false
end

-- Plays a sound from a spot in the world. Returns false if it was skipped
-- (rate limit, or too far away to hear).
function SoundController:PlayAt(name: string, position: Vector3): boolean
	local entry = entries[name]
	return if entry then play(entry, position) else false
end

return SoundController
