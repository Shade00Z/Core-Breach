-- QuestService
-- NPC quests (QuestConfig): each layer's quest giver hands out a line of 5
-- quests, one at a time, in order. Talk to them (QuestController) to take
-- the next quest; when it's done, talk to them again to turn it in.
--
-- Progress only counts for your current layer's quest line, and only while
-- a quest is active. Other services report what you did with
-- QuestService:Progress(player, kind, amount, detail):
--   kills / heroKills   WaveService.EnemyKilled (hooked here)
--   waves               WaveService.WaveCleared (hooked here)
--   mine                MiningService (detail = ore id)
--   forge               ForgeService
--   boss                BossService (detail = the boss's layer)
--
-- The client gets { quest = {...} } stats: which quest you're on and how far
-- along you are. The dialogue text lives in QuestConfig on the client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local QuestConfig = require(Shared:WaitForChild("QuestConfig"))
local LayerConfig = require(Shared:WaitForChild("LayerConfig"))
local HeroConfig = require(Shared:WaitForChild("HeroConfig"))
local Config = require(Shared:WaitForChild("ProgressionConfig"))
local Format = require(Shared:WaitForChild("Format"))

local TALK_DISTANCE = 16 -- studs from the quest giver to accept or turn in
local PUSH_INTERVAL = 0.25 -- kills come fast; send progress at most this often
local ACTION_COOLDOWN = 0.5

local QuestService = {}

local services
local notify: RemoteEvent
local dirty: { [Player]: boolean } = {}
local lastAction: { [Player]: number } = {}

type QuestState = { step: number, active: boolean, progress: number }

-- Your quest line in a layer (created on first use)
local function stateFor(player: Player, layer: number): QuestState
	local data = services.DataService:Get(player)
	local key = tostring(layer)
	local state = data.quests[key]
	if not state then
		state = { step = 1, active = false, progress = 0 }
		data.quests[key] = state
	end
	return state
end

local function currentLayer(player: Player): number
	return LayerConfig.Get(services.DataService:Get(player).layer).id
end

local function push(player: Player)
	local layer = currentLayer(player)
	local state = stateFor(player, layer)
	local line = QuestConfig.Lines[layer]
	services.EconomyService:PushStats(player, {
		quest = {
			layer = layer,
			step = state.step,
			total = if line then #line.quests else 0,
			active = state.active,
			progress = state.progress,
		},
	})
end

function QuestService:Refresh(player: Player)
	push(player)
end

local function giveReward(player: Player, quest: QuestConfig.Quest): (number, number)
	local data = services.DataService:Get(player)
	local xp = HeroConfig.XPToNext(data.level) * quest.reward.xpLevels
	local multiplier = data.coinMultiplier * LayerConfig.Get(data.layer).coinMultiplier
	local coins = Config.CoinsForWave(math.max(1, data.wave - 1), multiplier) * quest.reward.coinWaves
	services.CharacterService:GiveXP(player, xp)
	services.EconomyService:AddCoins(player, coins)
	return xp, coins
end

local function complete(player: Player, state: QuestState, quest: QuestConfig.Quest)
	local xp, coins = giveReward(player, quest)
	state.step += 1
	state.active = false
	state.progress = 0
	notify:FireClient(player, string.format("Quest complete: %s! +%s XP, +$%s", quest.title, Format.Number(math.floor(xp)), Format.Number(math.floor(coins))))
	push(player)
end

-- Something quest-worthy happened. Counts toward the active quest in the
-- player's current layer if it's the right kind.
function QuestService:Progress(player: Player, kind: string, amount: number, detail: any?)
	if not services.DataService:IsLoaded(player) then
		return
	end
	local layer = currentLayer(player)
	local state = stateFor(player, layer)
	if not state.active then
		return
	end
	local quest = QuestConfig.Get(layer, state.step)
	if not quest or quest.kind ~= kind then
		return
	end
	if kind == "mine" and quest.item and quest.item ~= detail then
		return
	end
	if kind == "boss" and detail ~= layer then
		return
	end
	if state.progress >= quest.count then
		return
	end
	state.progress = math.min(quest.count, state.progress + amount)
	if state.progress >= quest.count then
		if quest.autoTurnIn then
			complete(player, state, quest)
			return
		end
		local giver = QuestConfig.Lines[layer].giver
		notify:FireClient(player, string.format("Quest done: %s! Go back to %s to turn it in.", quest.title, giver))
		push(player)
	else
		dirty[player] = true
	end
end

-- Must be standing near your layer's quest giver
local function nearGiver(player: Player, layer: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local giver = services.HubService:GetHub(layer).questGiver
	local body = giver and giver.PrimaryPart
	return root ~= nil and body ~= nil and ((root :: BasePart).Position - body.Position).Magnitude <= TALK_DISTANCE
end

local function onAction(player: Player, action: unknown)
	local now = os.clock()
	if lastAction[player] and now - lastAction[player] < ACTION_COOLDOWN then
		return
	end
	lastAction[player] = now
	local layer = currentLayer(player)
	if not nearGiver(player, layer) then
		return
	end
	local state = stateFor(player, layer)
	local quest = QuestConfig.Get(layer, state.step)
	if not quest then
		return
	end
	if action == "Accept" and not state.active then
		state.active = true
		state.progress = 0
		notify:FireClient(player, "Quest accepted: " .. quest.title)
		push(player)
	elseif action == "TurnIn" and state.active and state.progress >= quest.count then
		complete(player, state, quest)
	end
end

-- Dev cheat: finish the current step of your active quest
function QuestService:DevComplete(player: Player)
	local layer = currentLayer(player)
	local state = stateFor(player, layer)
	local quest = QuestConfig.Get(layer, state.step)
	if quest and state.active then
		self:Progress(player, quest.kind, quest.count, if quest.kind == "mine" then quest.item elseif quest.kind == "boss" then layer else nil)
	end
end

function QuestService:Init(allServices)
	services = allServices
end

function QuestService:Start()
	notify = Remotes.Event("Notify")
	Remotes.Event("QuestAction").OnServerEvent:Connect(onAction)

	local WaveService = services.WaveService
	WaveService.EnemyKilled:Connect(function(lane, _, source)
		QuestService:Progress(lane.owner, "kills", 1)
		if source == "hero" then
			QuestService:Progress(lane.owner, "heroKills", 1)
		end
	end)
	WaveService.WaveCleared:Connect(function(lane)
		QuestService:Progress(lane.owner, "waves", 1)
	end)

	local DataService = services.DataService
	DataService.Loaded:Connect(push)
	for _, player in Players:GetPlayers() do
		if DataService:IsLoaded(player) then
			push(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		lastAction[player] = nil
	end)

	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer += dt
		if timer < PUSH_INTERVAL then
			return
		end
		timer = 0
		for player in dirty do
			dirty[player] = nil
			if player.Parent == Players and DataService:IsLoaded(player) then
				push(player)
			end
		end
	end)
end

return QuestService
