-- FXBatcher
-- Collects shots, kills and coin pickups for each player and sends them in
-- one packed LaneFX message about 20 times a second, instead of one message
-- per event. Format: shared/FXPacket.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FXPacket = require(Shared:WaitForChild("FXPacket"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local SEND_INTERVAL = 0.05
local MAX_PER_BATCH = 250 -- safety cap per list per message

type Batch = { shots: { FXPacket.Shot }, kills: { FXPacket.Kill }, pickups: { number } }

local FXBatcher = {}

local batches: { [Player]: Batch } = {}
local started = false

local function batchFor(player: Player): Batch
	local batch = batches[player]
	if not batch then
		batch = { shots = {}, kills = {}, pickups = {} }
		batches[player] = batch
	end
	return batch
end

function FXBatcher.Shot(player: Player, slot: number, enemyId: number, x: number, z: number)
	local batch = batchFor(player)
	if #batch.shots < MAX_PER_BATCH then
		table.insert(batch.shots, { slot = slot, enemyId = enemyId, x = x, z = z })
	end
end

-- dropId 0 = this kill dropped no coins
function FXBatcher.Kill(player: Player, kill: FXPacket.Kill)
	local batch = batchFor(player)
	if #batch.kills < MAX_PER_BATCH then
		table.insert(batch.kills, kill)
	end
end

-- Pickups are never dropped from a batch: the client must hear about every one.
function FXBatcher.Pickup(player: Player, dropId: number)
	table.insert(batchFor(player).pickups, dropId)
end

function FXBatcher.Start()
	if started then
		return
	end
	started = true
	local remote = Remotes.Event("LaneFX")
	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer += dt
		if timer < SEND_INTERVAL then
			return
		end
		timer = 0
		for player, batch in batches do
			if #batch.shots > 0 or #batch.kills > 0 or #batch.pickups > 0 then
				if player.Parent == Players then
					remote:FireClient(player, FXPacket.Encode(batch.shots, batch.kills, batch.pickups))
				end
				table.clear(batch.shots)
				table.clear(batch.kills)
				table.clear(batch.pickups)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		batches[player] = nil
	end)
end

return FXBatcher
