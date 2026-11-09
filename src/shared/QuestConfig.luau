-- QuestConfig
-- Each layer's quest line: 5 quests from the quest giver at that layer's
-- outpost, taken one at a time and in order. Talk to the giver to take the
-- next quest, do it, then come back and turn it in for XP and coins.
--
-- Quest kinds (what counts toward it):
--   kills      enemies killed in your lane (by anything)
--   heroKills  enemies killed by your own pickaxe or Fire Blast
--   mine       ore mined (item = which ore)
--   forge      forge strikes
--   waves      waves beaten in your lane
--   boss       beating this layer's boss (turned in automatically, since the
--              floor seal drops you into the next layer)
--
-- Rewards grow with you, so a quest is always worth doing:
--   XP    = xpLevels x the XP for your next level
--   coins = coinWaves x what one of your current waves pays

local LootConfig = require(script.Parent:WaitForChild("LootConfig"))
local LayerConfig = require(script.Parent:WaitForChild("LayerConfig"))

export type Quest = {
	title: string,
	kind: "kills" | "heroKills" | "mine" | "forge" | "waves" | "boss",
	item: string?, -- for "mine"
	count: number,
	offer: string, -- what the giver says when offering it
	reminder: string, -- while you're working on it
	done: string, -- when you bring it back
	reward: { xpLevels: number, coinWaves: number },
	autoTurnIn: boolean?,
}

export type Line = {
	giver: string,
	allDone: string, -- after the last quest
	elsewhere: string, -- talking to them while you play in another layer
	quests: { Quest },
}

local QuestConfig = {}

QuestConfig.Lines = {
	-- Layer 1: Topsoil
	[1] = {
		giver = "Foreman Rusk",
		allDone = "You broke the seal. Whatever's pounding up from the core, it's below us now. Watch yourself down there, kid.",
		elsewhere = "You're working a deeper layer now. Go see whoever runs the outpost down there.",
		quests = {
			{
				title = "Pest Control",
				kind = "kills",
				count = 50,
				offer = "New face, huh? Name's Rusk. Ever since the core started breaching, grubs have been chewing through every tunnel we dig. Clear 50 of them out of your lane and I'll make it worth your while.",
				reminder = "Those grubs won't clear themselves. Your gear wall does most of the work, just keep it running.",
				done = "Ha! The tunnels are quieter already. Here's your pay.",
				reward = { xpLevels = 1, coinWaves = 3 },
			},
			{
				title = "Swing It Yourself",
				kind = "heroKills",
				count = 20,
				offer = "Your gear does the heavy lifting, but a real miner knows how to swing. Hop over your barricade and take down 20 of them with your own pickaxe or a Fire Blast.",
				reminder = "Jump the barricade and get your hands dirty. Pickaxe or Fire Blast, both count.",
				done = "Now that's a miner. Keep that arm strong.",
				reward = { xpLevels = 1, coinWaves = 3 },
			},
			{
				title = "Copper for the Rails",
				kind = "mine",
				item = "copper_ore",
				count = 30,
				offer = "We're laying new rails down to the deep shafts. Bring up 30 Copper Ore from the mine, west of the plaza. Swing at the veins until they crack.",
				reminder = "The copper veins are in the mine, west of the plaza. Everyone who hits a vein gets the ore.",
				done = "Good copper. The rails'll be done in no time.",
				reward = { xpLevels = 1.5, coinWaves = 4 },
			},
			{
				title = "Hot Metal",
				kind = "forge",
				count = 1,
				offer = "See the forge by the mine? Feed it loot and strike one of your gear. More loot, bigger multiplier. Do it once and I'll know you've got the knack.",
				reminder = "The forge is by the mine entrance. Pick a gear, add loot, then STRIKE.",
				done = "Feel that? That's what a forged weapon hits like.",
				reward = { xpLevels = 1.5, coinWaves = 4 },
			},
			{
				title = "The Thing Below",
				kind = "boss",
				count = 1,
				offer = "Something big keeps pounding on the floor seal in the arena, south of here. We call it Rootmaw. Get to level 30, challenge it at the seal, and bring a friend if you can. Beat it and the seal breaks open to the Stone Vault.",
				reminder = "Rootmaw waits under the seal in the arena, south of the plaza. You'll need level 30.",
				done = "You actually did it. The way down is open.",
				reward = { xpLevels = 2, coinWaves = 6 },
				autoTurnIn = true,
			},
		},
	},

	-- Layer 2: Stone Vault
	[2] = {
		giver = "Warden Sela",
		allDone = "That's every job I have. The vault's boss sleeps until the way to the Magma Belt opens. Soon.",
		elsewhere = "You don't work this layer anymore.",
		quests = {
			{
				title = "Vault Sweep",
				kind = "kills",
				count = 150,
				offer = "So you're the one who cracked Rusk's seal. I'm Sela, I keep the Stone Vault. Golems and bats are pouring out of every crack. Clear 150 out of your lane.",
				reminder = "Golems are slow but tough. Bats are fast. Keep your wall strong.",
				done = "Not bad for a topsider. Here.",
				reward = { xpLevels = 1, coinWaves = 3 },
			},
			{
				title = "Crystal Haul",
				kind = "mine",
				item = "crystal_ore",
				count = 20,
				offer = "Vault Crystal is worth more to the forge than anything up top. Mine 20 from the far end of the mine. You'll need at least an Iron Pickaxe.",
				reminder = "Vault Crystal is at the far end of the mine and needs an Iron Pickaxe (upgrade at the forge).",
				done = "Look at that shine. Forge it into something nasty.",
				reward = { xpLevels = 1.5, coinWaves = 4 },
			},
			{
				title = "Batting Practice",
				kind = "heroKills",
				count = 40,
				offer = "Bats are quick, but they don't like a pickaxe to the face. Take down 40 enemies yourself.",
				reminder = "Pickaxe or Fire Blast, 40 of them. Bats come in low, so swing early.",
				done = "Your swing's getting sharp.",
				reward = { xpLevels = 1.5, coinWaves = 4 },
			},
			{
				title = "Deep Push",
				kind = "waves",
				count = 15,
				offer = "The deeper waves get nasty, and I need someone who can hold a lane. Beat 15 waves.",
				reminder = "Keep beating waves. Losing one doesn't reset your count.",
				done = "Fifteen waves and still standing. Good.",
				reward = { xpLevels = 2, coinWaves = 6 },
			},
			{
				title = "Sharpen Up",
				kind = "forge",
				count = 3,
				offer = "Whatever's below us will chew through plain gear. Strike the forge 3 times. Crystal makes a fine forge feed.",
				reminder = "Three forge strikes. Any gear, any loot.",
				done = "Now you're ready for what's coming.",
				reward = { xpLevels = 2, coinWaves = 6 },
			},
		},
	},
} :: { [number]: Line }

-- One line describing what a quest needs ("Mine 30 Copper Ore")
function QuestConfig.Describe(quest: Quest, layer: number?): string
	if quest.kind == "kills" then
		return string.format("Defeat %d enemies in your lane", quest.count)
	elseif quest.kind == "heroKills" then
		return string.format("Defeat %d enemies with your pickaxe or Fire Blast", quest.count)
	elseif quest.kind == "mine" then
		local item = quest.item and LootConfig.Items[quest.item]
		return string.format("Mine %d %s", quest.count, if item then item.name else "ore")
	elseif quest.kind == "forge" then
		return if quest.count == 1 then "Strike the forge once" else string.format("Strike the forge %d times", quest.count)
	elseif quest.kind == "waves" then
		return string.format("Beat %d waves in your lane", quest.count)
	elseif quest.kind == "boss" then
		local boss = LayerConfig.Get(layer).boss
		return if boss then string.format("Defeat %s (level %d) in the arena", boss.name, boss.level) else "Defeat the layer boss"
	end
	return ""
end

function QuestConfig.Get(layer: number, step: number): Quest?
	local line = QuestConfig.Lines[layer]
	return line and line.quests[step]
end

return QuestConfig
