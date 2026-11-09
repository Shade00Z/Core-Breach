-- SoundConfig
-- Every sound effect in one place. To change a sound, swap its id for any
-- free audio from the Creator Store (Studio: Toolbox > Audio).
--
--   id            Roblox audio asset id
--   volume        0-1
--   pitch         {min, max}: a random pitch each play, so repeats don't sound robotic
--   maxPerSecond  limits how often it can play (fast guns would otherwise be deafening)
--   voices        how many copies can overlap
--   range         {min, max} in studs: makes the sound come from a spot in the
--                 world (use SoundController:PlayAt). Full volume up to min,
--                 fading to silent at max. Leave out for UI-style sounds.

export type SoundInfo = {
	id: number,
	volume: number,
	pitch: { number }?,
	maxPerSecond: number?,
	voices: number?,
	range: { number }?,
}

local SoundConfig = {}

SoundConfig.Sounds = {
	-- Combat
	Shot = { id = 4400449399, volume = 0.16, pitch = { 0.9, 1.15 }, maxPerSecond = 14, voices = 8, range = { 20, 140 } }, -- Laser Gunshot
	BarricadeHit = { id = 9120888980, volume = 0.35, pitch = { 0.9, 1.1 }, maxPerSecond = 4, voices = 3, range = { 25, 160 } }, -- ProSoundEffects wood hit
	BarricadeBreak = { id = 9113225986, volume = 0.6, voices = 1, range = { 30, 200 } }, -- ProSoundEffects giant axe impact
	BossRoar = { id = 9113980319, volume = 0.5, voices = 1 }, -- ProSoundEffects monster roar
	BossDown = { id = 120005759558278, volume = 0.5, voices = 1 }, -- Milestone
	BossSlam = { id = 9113225986, volume = 0.7, pitch = { 0.7, 0.8 }, voices = 2, range = { 30, 220 } }, -- giant axe impact, lower (layer boss slam)

	-- Hero
	Swing = { id = 5789211405, volume = 0.35, pitch = { 0.95, 1.1 }, voices = 2 }, -- sword whoosh
	MeleeHit = { id = 100970228713833, volume = 0.4, pitch = { 0.9, 1.1 }, maxPerSecond = 6, voices = 3 }, -- heavy punch
	HeroHurt = { id = 99238364534468, volume = 0.45, pitch = { 0.9, 1.05 }, maxPerSecond = 4, voices = 2 }, -- hit
	FireCast = { id = 9114446852, volume = 0.45, voices = 2 }, -- ProSoundEffects fire whoosh
	FireExplode = { id = 113076931050699, volume = 0.55, voices = 2, range = { 30, 200 } }, -- fire explosion

	-- Digging
	RockHit = { id = 9118608146, volume = 0.5, pitch = { 0.9, 1.15 }, voices = 3, range = { 15, 120 } }, -- ProSoundEffects rock hits
	RockBreak = { id = 9118588165, volume = 0.7, voices = 1, range = { 20, 160 } }, -- ProSoundEffects rock breaks
	Purchase = { id = 134810204798705, volume = 0.4, voices = 1 }, -- cash register
	Anvil = { id = 9116651255, volume = 0.6, pitch = { 0.9, 1.05 }, voices = 2 }, -- ProSoundEffects metal hits (forge strike)

	-- Coins
	CoinPickup = { id = 93529351909119, volume = 0.25, pitch = { 0.95, 1.2 }, maxPerSecond = 10, voices = 5 }, -- retro coin

	-- Crate
	RollStart = { id = 138269694368715, volume = 0.35, voices = 1 }, -- whoosh spin
	RevealCommon = { id = 90618709727045, volume = 0.35, voices = 1 }, -- small reveal
	RevealEpic = { id = 117904822279498, volume = 0.5, voices = 1 }, -- reward chime
	RevealLegendary = { id = 1840076509, volume = 0.6, voices = 1 }, -- APM sting "Through the Roof"

	-- Progress
	LevelUp = { id = 120005759558278, volume = 0.45, pitch = { 1.1, 1.1 }, voices = 1 }, -- Milestone, higher
	NewRecord = { id = 120005759558278, volume = 0.5, voices = 1 }, -- Milestone
	Rebirth = { id = 1841997734, volume = 0.5, voices = 1 }, -- APM sting "Micro"
	QuestAccept = { id = 90618709727045, volume = 0.35, voices = 1 }, -- small reveal
	QuestDone = { id = 117904822279498, volume = 0.5, voices = 1 }, -- reward chime
} :: { [string]: SoundInfo }

return SoundConfig
