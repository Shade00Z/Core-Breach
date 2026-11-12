-- StoreController
-- The Store screen (HUD button "Store"): every gamepass in StoreConfig with
-- its price, a Buy button, and On / Off switches for the ones you can toggle.
-- Buying and switching happen on the server (StoreService); this only shows
-- what the server says you own ({ store = ... } stats).
-- The panel is rebuilt only when something you'd click changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local StoreConfig = require(Shared:WaitForChild("StoreConfig"))
local UIKit = require(script.Parent.Parent:WaitForChild("UIKit"))

local ROBUX_BLUE = Color3.fromRGB(40, 120, 190)

local StoreController = {}

local UIController
local actionRemote: RemoteEvent
local panel: UIKit.Panel
local builtKey = ""

local function storeStats()
	local store = UIController.Stats.store
	return if type(store) == "table" then store else nil
end

local function stateKey(store): string
	local parts = { tostring(store.tokens), tostring(store.restricted), tostring(store.skip.robux) }
	for _, pass in StoreConfig.Passes do
		table.insert(parts, string.format("%s%s%s%s", pass.key, tostring(store.owned[pass.key]), tostring(store.settings[pass.key]), tostring(store.prices[pass.key])))
	end
	table.insert(parts, tostring(store.settings.skipBelow))
	return table.concat(parts, "|")
end

local function build(store)
	UIKit.Clear(panel.body)
	local C = UIKit.Colors
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	UIKit.Label(panel.body, "Boosts and time-savers. Nothing here changes your luck or your rolls.", 14, C.Dim, nextOrder())
	if store.coinBoost > 1 then
		UIKit.Label(panel.body, string.format("Your coin boost: x%d", store.coinBoost), 15, Color3.fromRGB(150, 255, 170), nextOrder())
	end

	for _, pass in StoreConfig.Passes do
		local has = store.owned[pass.key] == true
		local row = UIKit.Row(panel.body, nextOrder())
		local header = Instance.new("Frame")
		header.BackgroundTransparency = 1
		header.Size = UDim2.new(1, 0, 0, 36)
		header.Parent = row
		local name = UIKit.Label(header, pass.name, 18, if has then C.Gold else nil)
		name.Size = UDim2.new(1, -250, 1, 0)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.TextYAlignment = Enum.TextYAlignment.Center

		local function rightButton(text: string, color: Color3, offset: number, width: number, onClick: () -> ()): TextButton
			local b = UIKit.Button(header, text, color, UDim2.new(0, width, 0, 34), onClick)
			b.Position = UDim2.new(1, -offset - width, 0, 1)
			b.TextSize = 15
			return b
		end

		if not has then
			local forSale = store.forSale[pass.key]
			local text = if forSale then "R$ " .. tostring(store.prices[pass.key]) elseif store.testing then "Test it" else "Coming soon"
			local b = rightButton(text, if forSale or store.testing then ROBUX_BLUE else C.Gray, 0, 120, function()
				actionRemote:FireServer("Buy", pass.key)
			end)
			b.AutoButtonColor = forSale or store.testing
		elseif pass.kind == "toggle" then
			local on = store.settings[pass.key] ~= false
			rightButton(if on then "On" else "Off", if on then C.Green else C.Gray, 0, 70, function()
				actionRemote:FireServer("Set", pass.key, not on)
			end)
			if pass.key == "autoSkip" then
				local current = store.settings.skipBelow
				rightButton("Below " .. tostring(current), C.Row:Lerp(Color3.new(1, 1, 1), 0.15), 78, 150, function()
					local index = table.find(StoreConfig.SkipBelow, current) or 0
					actionRemote:FireServer("Set", "skipBelow", StoreConfig.SkipBelow[index % #StoreConfig.SkipBelow + 1])
				end)
			end
		else
			local replaced = pass.kind == "coins" and (pass.coins or 1) < store.coinBoost
			local tag = UIKit.Label(header, if replaced then "Replaced" else "Owned", 15, if replaced then C.Dim else Color3.fromRGB(150, 255, 170))
			tag.Size = UDim2.new(0, 120, 1, 0)
			tag.Position = UDim2.new(1, -120, 0, 0)
			tag.AutomaticSize = Enum.AutomaticSize.None
			tag.TextXAlignment = Enum.TextXAlignment.Right
			tag.TextYAlignment = Enum.TextYAlignment.Center
		end
		-- Testing only: owned test passes can be switched back off
		if has and store.testing and not store.forSale[pass.key] and pass.kind ~= "toggle" then
			rightButton("Test off", C.Gray, 128, 90, function()
				actionRemote:FireServer("Buy", pass.key)
			end)
		end
		UIKit.Label(row, pass.description, 13, C.Dim)
	end

	if not store.restricted then
		local skip = StoreConfig.PriceSkip
		local row = UIKit.Row(panel.body, nextOrder())
		UIKit.Label(row, string.format("%s  ·  R$ %d each", skip.name, store.skip.robux), 18)
		UIKit.Label(row, skip.description .. " Use the blue button on the crate's reveal panel." .. (if store.tokens > 0 then string.format("  You have %d token%s.", store.tokens, if store.tokens == 1 then "" else "s") else ""), 13, C.Dim)
	end
end

local function refresh()
	local store = storeStats()
	if not store or not panel.frame.Visible then
		return
	end
	local key = stateKey(store)
	if key ~= builtKey then
		builtKey = key
		build(store)
	end
end

function StoreController:Init(controllers)
	UIController = controllers.UIController
	local gui = UIController:GetGui()
	panel = UIKit.Panel(gui, "StorePanel", "Store", 560, 480)
	-- One wide button under the two columns of HUD buttons
	local toggle = UIKit.HudButton(gui, "Store", ROBUX_BLUE, UDim2.new(0, 12, 0.5, 124))
	toggle.Size = UDim2.new(0, 188, 0, 36)
	toggle.Activated:Connect(function()
		if panel.frame.Visible then
			panel.close()
		else
			panel.open()
			builtKey = ""
			refresh()
		end
	end)
end

function StoreController:Start()
	actionRemote = Remotes.Event("StoreAction")
	local last = nil
	UIController.StatsUpdated:Connect(function(stats)
		if stats.store ~= last then
			last = stats.store
			refresh()
		end
	end)
end

return StoreController
