-- StoreService
-- The Robux store (StoreConfig): gamepasses and the Price Skip product.
-- Boosts and convenience only; nothing here changes roll odds.
--
--   * Passes: checked with Roblox when you join, and granted the moment a
--     purchase finishes. Other services ask :Has(player, key) (owned) or
--     :On(player, key) (owned and switched on).
--       coins2/4/8   EconomyService multiplies coins by :CoinBoost
--       autoCollect  EconomyService picks coins up for you
--       autoOpen     this service rolls your crate whenever nothing is waiting
--       autoSkip     CrateService skips rolls below your chosen rarity
--       fastRolls    CrateService: shorter cooldown, no reveal suspense
--       offline      EconomyService: longer offline earnings (:OfflineHours)
--       speed2       your lane runs at double speed
--   * Price Skip: a developer product. Paying takes the gear waiting at your
--     crate for free. If nothing is waiting by the time the purchase arrives
--     it becomes a Price Skip token you can use on a later roll, so a paid
--     purchase is never lost. Every receipt is recorded in the save so it
--     can't be granted twice.
--   * PolicyService: where paid random items are restricted, Price Skip is
--     hidden (it's Robux for an item that came out of a random roll).
--
-- While an ID in StoreConfig is 0 the item isn't for sale. In Studio / debug
-- mode, "buying" it just toggles it on for this session so it can be tested.
--
-- The client gets { store = { owned, settings, tokens, restricted, prices,
-- forSale, skip = { robux, forSale }, coinBoost, testing } } stats.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local StoreConfig = require(Shared:WaitForChild("StoreConfig"))
local DebugConfig = require(Shared:WaitForChild("DebugConfig"))
local GearData = require(Shared:WaitForChild("GearData"))

local ACTION_COOLDOWN = 0.25
local AUTO_OPEN_INTERVAL = 0.2
local RECEIPTS_KEPT = 60
local LOAD_WAIT = 6 -- seconds :WaitLoaded gives the ownership checks

local StoreService = {}

local services
local notify: RemoteEvent
local owned: { [Player]: { [string]: boolean } } = {}
local restricted: { [Player]: boolean } = {}
local ready: { [Player]: boolean } = {}
local lastAction: { [Player]: number } = {}
local prices: { [string]: number } = {} -- pass key -> Robux (real price once loaded)
local skipRobux = StoreConfig.PriceSkip.robux

local function storeData(player: Player)
	return services.DataService:Get(player).store
end

------------------------------------------------------------------------
-- What other services ask
------------------------------------------------------------------------

function StoreService:Has(player: Player, key: string): boolean
	local mine = owned[player]
	return mine ~= nil and mine[key] == true
end

-- Owned and switched on
function StoreService:On(player: Player, key: string): boolean
	return self:Has(player, key) and storeData(player).settings[key] ~= false
end

function StoreService:CoinBoost(player: Player): number
	local mine = owned[player]
	return if mine then StoreConfig.CoinBoost(mine) else 1
end

function StoreService:OfflineExtraHours(player: Player): number
	return if self:Has(player, "offline") then StoreConfig.OfflineExtraHours else 0
end

-- Rarity order below which Auto-Skip throws a roll away (0 = it's off)
function StoreService:SkipBelowOrder(player: Player): number
	if not self:On(player, "autoSkip") then
		return 0
	end
	local rarity = GearData.Rarities[storeData(player).settings.skipBelow]
	return if rarity then rarity.order else 0
end

-- Waits (briefly) until this player's passes have been checked
function StoreService:WaitLoaded(player: Player)
	local started = os.clock()
	while not ready[player] and player.Parent == Players and os.clock() - started < LOAD_WAIT do
		task.wait(0.1)
	end
end

------------------------------------------------------------------------

local function push(player: Player)
	local data = storeData(player)
	local forSale = {}
	for _, pass in StoreConfig.Passes do
		forSale[pass.key] = pass.gamePassId > 0
	end
	services.EconomyService:PushStats(player, {
		store = {
			owned = table.clone(owned[player] or {}),
			settings = table.clone(data.settings),
			tokens = data.tokens,
			restricted = restricted[player] == true,
			prices = prices,
			forSale = forSale,
			skip = { robux = skipRobux, forSale = StoreConfig.PriceSkip.productId > 0 },
			coinBoost = StoreService:CoinBoost(player),
			testing = DebugConfig.IsActive(player),
		},
	})
end

function StoreService:Refresh(player: Player)
	push(player)
end

local function applySpeed(player: Player)
	local lane = services.WaveService:GetLane(player)
	if lane then
		lane.timeScale = if StoreService:On(player, "speed2") then StoreConfig.GameSpeed else 1
	end
end

local function grant(player: Player, key: string, announce: boolean)
	local mine = owned[player]
	if not mine or mine[key] then
		return
	end
	mine[key] = true
	storeData(player).owned[key] = true
	applySpeed(player)
	push(player)
	if announce then
		notify:FireClient(player, StoreConfig.ByKey[key].name .. " unlocked! Thank you.")
	end
end

-- On join: ask Roblox which passes this player owns. If Roblox can't be
-- reached, fall back to what their save remembers.
local function loadPlayer(player: Player)
	local data = storeData(player)
	local mine = {}
	for _, pass in StoreConfig.Passes do
		if data.owned[pass.key] then
			mine[pass.key] = true
		elseif pass.gamePassId > 0 then
			local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.gamePassId)
			if ok and has then
				mine[pass.key] = true
				data.owned[pass.key] = true
			end
		end
	end
	-- Policy: assume restricted if Roblox doesn't answer
	local ok, policy = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	restricted[player] = not ok or policy.ArePaidRandomItemsRestricted == true
	if player.Parent ~= Players then
		return
	end
	owned[player] = mine
	ready[player] = true
	applySpeed(player)
	push(player)
end

------------------------------------------------------------------------
-- Price Skip
------------------------------------------------------------------------

-- Takes the waiting roll for free if there is one; otherwise banks a token
local function grantPriceSkip(player: Player)
	if services.CrateService:TakeFree(player) then
		return
	end
	local data = storeData(player)
	data.tokens += 1
	notify:FireClient(player, "No roll was waiting, so you got a Price Skip token. Use it on any roll.")
	push(player)
end

local function processReceipt(info): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player or not services.DataService:IsLoaded(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if info.ProductId ~= StoreConfig.PriceSkip.productId then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = storeData(player)
	if table.find(data.receipts, info.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already handled
	end
	table.insert(data.receipts, info.PurchaseId)
	while #data.receipts > RECEIPTS_KEPT do
		table.remove(data.receipts, 1)
	end
	grantPriceSkip(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

------------------------------------------------------------------------
-- Requests from the Store screen
------------------------------------------------------------------------

local function onAction(player: Player, action: unknown, key: unknown, value: unknown)
	if not services.DataService:IsLoaded(player) or not ready[player] then
		return
	end
	local now = os.clock()
	if lastAction[player] and now - lastAction[player] < ACTION_COOLDOWN then
		return
	end
	lastAction[player] = now
	local data = storeData(player)
	local testing = DebugConfig.IsActive(player)

	if action == "Buy" and type(key) == "string" and StoreConfig.ByKey[key] then
		local pass = StoreConfig.ByKey[key]
		if pass.gamePassId > 0 then
			if not StoreService:Has(player, key) then
				MarketplaceService:PromptGamePassPurchase(player, pass.gamePassId)
			end
		elseif testing then
			-- Not created yet: toggle it for this session so it can be tested
			local mine = owned[player]
			mine[key] = if mine[key] then nil else true
			applySpeed(player)
			push(player)
			notify:FireClient(player, string.format("[TEST] %s %s", pass.name, if mine[key] then "on" else "off"))
		else
			notify:FireClient(player, pass.name .. " is coming soon.")
		end
	elseif action == "Set" and type(key) == "string" then
		if key == "skipBelow" then
			if type(value) == "string" and table.find(StoreConfig.SkipBelow, value) then
				data.settings.skipBelow = value
			end
		elseif StoreConfig.ByKey[key] and StoreConfig.ByKey[key].kind == "toggle" and type(value) == "boolean" then
			data.settings[key] = value
		end
		applySpeed(player)
		push(player)
	elseif action == "PriceSkip" then
		if restricted[player] or not services.CrateService:HasPaidRoll(player) then
			return
		end
		if data.tokens > 0 then
			if services.CrateService:TakeFree(player) then
				data.tokens -= 1
				push(player)
			end
		elseif StoreConfig.PriceSkip.productId > 0 then
			MarketplaceService:PromptProductPurchase(player, StoreConfig.PriceSkip.productId)
		elseif testing then
			grantPriceSkip(player)
		else
			notify:FireClient(player, "Price Skip is coming soon.")
		end
	end
end

------------------------------------------------------------------------

function StoreService:Init(allServices)
	services = allServices
	for _, pass in StoreConfig.Passes do
		prices[pass.key] = pass.robux
	end
end

function StoreService:Start()
	notify = Remotes.Event("Notify")
	Remotes.Event("StoreAction").OnServerEvent:Connect(onAction)
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if not wasPurchased then
			return
		end
		for _, pass in StoreConfig.Passes do
			if pass.gamePassId == gamePassId then
				grant(player, pass.key, true)
			end
		end
	end)

	local DataService = services.DataService
	DataService.Loaded:Connect(loadPlayer)
	for _, player in Players:GetPlayers() do
		if DataService:IsLoaded(player) then
			task.spawn(loadPlayer, player)
		end
	end
	services.WaveService.LaneCreated:Connect(function(lane)
		if ready[lane.owner] then
			applySpeed(lane.owner)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		restricted[player] = nil
		ready[player] = nil
		lastAction[player] = nil
	end)

	-- Real prices from Roblox (the Store shows StoreConfig's until these arrive)
	task.spawn(function()
		for _, pass in StoreConfig.Passes do
			if pass.gamePassId > 0 then
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, pass.gamePassId, Enum.InfoType.GamePass)
				if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
					prices[pass.key] = info.PriceInRobux
				end
			end
		end
		if StoreConfig.PriceSkip.productId > 0 then
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, StoreConfig.PriceSkip.productId, Enum.InfoType.Product)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				skipRobux = info.PriceInRobux
			end
		end
		for player in ready do
			push(player)
		end
	end)

	-- Auto-Open: roll whenever nothing is waiting (CrateService keeps the cooldown)
	task.spawn(function()
		while true do
			task.wait(AUTO_OPEN_INTERVAL)
			for player in ready do
				if player.Parent == Players and StoreService:On(player, "autoOpen") then
					services.CrateService:Roll(player, false, true)
				end
			end
		end
	end)
end

return StoreService
