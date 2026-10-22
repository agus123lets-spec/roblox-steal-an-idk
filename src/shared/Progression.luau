--!strict
-- Pure progression math shared by server and client (and unit-tested with Lune):
-- rebirths, Index bonuses, fusion, daily rewards, daily quests and codes.

local Config = require(script.Parent.Config)
local PetLogic = require(script.Parent.PetLogic)
local Rng = require(script.Parent.Rng)

export type Quest = { id: string, target: number, progress: number, claimed: boolean, feathers: number }

local Progression = {}

---------------------------------------------------------------------------
-- Rebirths
---------------------------------------------------------------------------
-- Coins and Speed needed for the next rebirth.
function Progression.rebirthRequirement(rebirths: number): (number, number)
	local r = Config.Rebirth
	return r.baseCoins * r.coinsGrowth ^ rebirths, r.baseSpeed * r.speedGrowth ^ rebirths
end

function Progression.rebirthIncomeMultiplier(rebirths: number): number
	return 1 + Config.Rebirth.incomeBonus * rebirths
end

function Progression.rebirthTrainingMultiplier(rebirths: number): number
	return 1 + Config.Rebirth.trainingBonus * rebirths
end

---------------------------------------------------------------------------
-- Index & income boosts
---------------------------------------------------------------------------
function Progression.biomeComplete(index: { [string]: boolean }, biomeKey: string): boolean
	local found = false
	for _, pet in Config.Pets do
		if pet.biome == biomeKey then
			if not index[pet.key] then
				return false
			end
			found = true
		end
	end
	return found
end

function Progression.completedBiomes(index: { [string]: boolean }): number
	local count = 0
	for _, biome in Config.Biomes do
		if Progression.biomeComplete(index, biome.key) then
			count += 1
		end
	end
	return count
end

function Progression.discovered(index: { [string]: boolean }): number
	local count = 0
	for _, pet in Config.Pets do
		if index[pet.key] then
			count += 1
		end
	end
	return count
end

function Progression.friendMultiplier(friends: number): number
	return 1 + Config.Friends.bonusPerFriend * math.min(math.max(friends, 0), Config.Friends.maxFriends)
end

-- Rebirths x Index x friends. Server events are applied on top of this.
function Progression.incomeMultiplier(rebirths: number, index: { [string]: boolean }, friends: number): number
	local indexMult = 1 + Config.Index.biomeBonus * Progression.completedBiomes(index)
	return Progression.rebirthIncomeMultiplier(rebirths) * indexMult * Progression.friendMultiplier(friends)
end

---------------------------------------------------------------------------
-- Fusion
---------------------------------------------------------------------------
-- The weakest pets of `kind` a fusion would use (your best copies are kept), or nil.
function Progression.fuseSelection(pets: { PetLogic.PetData }, kind: string): { PetLogic.PetData }?
	local matching = {}
	for _, pet in pets do
		if pet.kind == kind then
			table.insert(matching, pet)
		end
	end
	local required = Config.Fusion.required
	if #matching < required then
		return nil
	end
	table.sort(matching, function(a, b)
		return PetLogic.income(a) < PetLogic.income(b)
	end)
	local selection = {}
	for i = 1, required do
		selection[i] = matching[i]
	end
	return selection
end

local function sizeIndex(key: string): number
	for index, info in Config.Sizes do
		if info.key == key then
			return index
		end
	end
	return 2
end

-- What a fusion makes: the next rarity from the same biome, keeping the best size and mutation.
-- Legendaries grow one size instead. Returns nil when nothing better exists.
function Progression.fuseResult(selection: { PetLogic.PetData }): (string?, string, string?)
	local first = selection[1]
	local info = if first then Config.PetByKey[first.kind] else nil
	if not info then
		return nil, "Normal", nil
	end
	local bestSize = 1
	local bestMutation: string? = nil
	local bestMult = 1
	for _, pet in selection do
		bestSize = math.max(bestSize, sizeIndex(pet.size))
		local mutation = PetLogic.mutationInfo(pet.mutation)
		if mutation and mutation.mult > bestMult then
			bestMutation = mutation.key
			bestMult = mutation.mult
		end
	end
	local order = Config.Rarities[info.rarity].order
	if order < #Config.RarityOrder then
		local upgraded = PetLogic.petFor(info.biome, Config.RarityOrder[order + 1])
		if upgraded then
			return upgraded.key, Config.Sizes[bestSize].key, bestMutation
		end
		return nil, "Normal", nil
	end
	if bestSize >= #Config.Sizes then
		return nil, Config.Sizes[bestSize].key, bestMutation
	end
	return info.key, Config.Sizes[bestSize + 1].key, bestMutation
end

---------------------------------------------------------------------------
-- Daily rewards
---------------------------------------------------------------------------
function Progression.canClaimDaily(last: number, now: number): boolean
	return last <= 0 or now - last >= Config.Daily.cooldown
end

function Progression.nextDailyAt(last: number): number
	return last + Config.Daily.cooldown
end

-- Streak after claiming now: it continues inside the streak window, otherwise starts over.
function Progression.nextStreak(last: number, streak: number, now: number): number
	if last > 0 and now - last <= Config.Daily.streakWindow then
		return streak + 1
	end
	return 1
end

function Progression.dailyReward(streak: number): Config.DailyReward
	local rewards = Config.Daily.rewards
	return rewards[(math.max(streak, 1) - 1) % #rewards + 1]
end

function Progression.dailyCoins(reward: Config.DailyReward, incomePerSecond: number): number
	local seconds = reward.coinsSeconds
	if not seconds then
		return 0
	end
	return math.max(reward.minCoins or 0, math.floor(incomePerSecond * seconds))
end

---------------------------------------------------------------------------
-- Daily quests
---------------------------------------------------------------------------
function Progression.questDay(now: number): number
	return math.floor(now / 86400)
end

function Progression.questInfo(id: string): Config.QuestInfo?
	for _, info in Config.Quests.pool do
		if info.id == id then
			return info
		end
	end
	return nil
end

function Progression.questText(id: string, target: number): string
	local info = Progression.questInfo(id)
	if not info then
		return id
	end
	if target == 1 and info.one then
		return info.one
	end
	return string.format(info.text, target)
end

-- The same player gets the same quests all day, on any server. At most one PvP quest a day.
function Progression.generateQuests(userId: number, day: number): { Quest }
	local rng = Rng.new(math.abs(userId) * 31 + day * 7919)
	local remaining = table.clone(Config.Quests.pool)
	local quests: { Quest } = {}
	local pvpPicked = false
	while #quests < Config.Quests.perDay do
		local candidates = {}
		local weights = {}
		for index, info in remaining do
			if not (info.pvp and pvpPicked) then
				table.insert(candidates, index)
				table.insert(weights, info.weight)
			end
		end
		if #candidates == 0 then
			break
		end
		local info = table.remove(remaining, candidates[PetLogic.pickIndex(rng.next, weights)])
		if info then
			pvpPicked = pvpPicked or info.pvp
			local target = rng.int(info.min, info.max)
			table.insert(quests, {
				id = info.id,
				target = target,
				progress = 0,
				claimed = false,
				feathers = info.feathers + (target - info.min) * 2,
			})
		end
	end
	return quests
end

---------------------------------------------------------------------------
-- Codes
---------------------------------------------------------------------------
function Progression.normalizeCode(text: string): string
	local stripped = string.gsub(text, "%s+", "")
	return string.upper(stripped)
end

return Progression
