--!strict
-- Pure game math (no Roblox services), shared by server and client and unit-tested with Lune.

local Config = require(script.Parent.Config)

export type PetData = { id: string, kind: string, size: string, mutation: string? }
export type RandomFn = () -> number

local PetLogic = {}

function PetLogic.sizeInfo(key: string): Config.SizeInfo?
	for _, info in Config.Sizes do
		if info.key == key then
			return info
		end
	end
	return nil
end

function PetLogic.mutationInfo(key: string?): Config.MutationInfo?
	if key == nil then
		return nil
	end
	for _, info in Config.Mutations do
		if info.key == key then
			return info
		end
	end
	return nil
end

function PetLogic.petFor(biome: string, rarity: string): Config.PetInfo?
	for _, info in Config.Pets do
		if info.biome == biome and info.rarity == rarity then
			return info
		end
	end
	return nil
end

function PetLogic.income(pet: PetData): number
	local info = Config.PetByKey[pet.kind]
	if not info then
		return 0
	end
	local size = PetLogic.sizeInfo(pet.size)
	local mutation = PetLogic.mutationInfo(pet.mutation)
	return info.income * (if size then size.mult else 1) * (if mutation then mutation.mult else 1)
end

function PetLogic.totalIncome(pets: { PetData }): number
	local total = 0
	for _, pet in pets do
		total += PetLogic.income(pet)
	end
	return total
end

function PetLogic.sellValue(pet: PetData): number
	return math.floor(PetLogic.income(pet) * Config.Economy.sellSeconds)
end

-- "Huge Diamond Tempest Drake"
function PetLogic.describe(pet: PetData): string
	local info = Config.PetByKey[pet.kind]
	local words = {}
	if pet.size ~= "Normal" then
		table.insert(words, pet.size)
	end
	if pet.mutation then
		table.insert(words, pet.mutation)
	end
	table.insert(words, if info then info.name else pet.kind)
	return table.concat(words, " ")
end

---------------------------------------------------------------------------
-- Rolling
---------------------------------------------------------------------------
function PetLogic.pickIndex(random: RandomFn, weights: { number }): number
	local total = 0
	for _, weight in weights do
		total += math.max(weight, 0)
	end
	if total <= 0 then
		return 1
	end
	local roll = random() * total
	for index, weight in weights do
		roll -= math.max(weight, 0)
		if roll < 0 then
			return index
		end
	end
	return #weights
end

-- Luck makes every rarity above Common more likely (Legendary is 4x at luck 2).
function PetLogic.rollEggRarity(random: RandomFn, luck: number): string
	local weights = {}
	for index, key in Config.RarityOrder do
		local info = Config.Rarities[key]
		weights[index] = info.spawnWeight * luck ^ ((info.order - 1) / 2)
	end
	return Config.RarityOrder[PetLogic.pickIndex(random, weights)]
end

function PetLogic.rollJackpotRarity(random: RandomFn): string
	local keys = {}
	local weights = {}
	for _, key in Config.RarityOrder do
		local weight = Config.Jackpot.rarityWeights[key]
		if weight then
			table.insert(keys, key)
			table.insert(weights, weight)
		end
	end
	return keys[PetLogic.pickIndex(random, weights)]
end

function PetLogic.rollSize(random: RandomFn, luck: number): string
	local weights = {}
	for index, info in Config.Sizes do
		weights[index] = if index >= 3 then info.weight * luck ^ ((index - 2) / 2) else info.weight
	end
	return Config.Sizes[PetLogic.pickIndex(random, weights)].key
end

function PetLogic.rollMutation(random: RandomFn, luck: number): string?
	for _, info in Config.Mutations do
		if random() < info.chance * luck then
			return info.key
		end
	end
	return nil
end

-- Returns pet kind, size, mutation and whether the egg got a lucky rarity upgrade.
function PetLogic.rollHatch(
	random: RandomFn,
	biome: string,
	rarity: string,
	luck: number,
	jackpot: boolean
): (string, string, string?, boolean)
	local finalRarity = rarity
	local lucky = false
	local rarityInfo = Config.Rarities[rarity]
	if rarityInfo and rarityInfo.order < #Config.RarityOrder and random() < Config.Hatch.luckyBumpChance * luck then
		finalRarity = Config.RarityOrder[rarityInfo.order + 1]
		lucky = true
	end
	local pet = PetLogic.petFor(biome, finalRarity) or PetLogic.petFor(biome, rarity)
	if not pet then
		error(`No pet configured for {biome}/{rarity}`)
	end
	local size = PetLogic.rollSize(random, luck)
	local mutationLuck = luck * (if jackpot then Config.Jackpot.mutationLuck else 1)
	local mutation = PetLogic.rollMutation(random, mutationLuck)
	return pet.key, size, mutation, lucky
end

---------------------------------------------------------------------------
-- Progression
---------------------------------------------------------------------------
-- Speed stat -> Humanoid.WalkSpeed. Logarithmic so huge Speed numbers stay playable.
function PetLogic.walkSpeedFor(speed: number): number
	local m = Config.Movement
	local walkSpeed = m.baseWalkSpeed + m.walkK * math.log(1 + math.max(speed, 0) / m.walkDivisor, 2)
	return math.min(walkSpeed, m.maxWalkSpeed)
end

function PetLogic.slotCost(currentSlots: number): number?
	if currentSlots >= Config.Plots.maxSlots then
		return nil
	end
	local step = currentSlots - Config.Plots.startSlots
	return math.floor(Config.Slots.baseCost * Config.Slots.growth ^ step)
end

-- Length of the track's centre line.
function PetLogic.trackPerimeter(): number
	local t = Config.Training
	return (t.outerX + t.innerX) + (t.outerZ + t.innerZ)
end

-- Fastest believable lap: hugging the infield with dashes. Faster laps are rejected.
function PetLogic.minLapTime(walkSpeed: number): number
	local t = Config.Training
	return 2 * (t.innerX + t.innerZ) / (math.max(walkSpeed, 1) * t.minTimeFactor)
end

function PetLogic.lapReward(trainingMult: number, lapTime: number, walkSpeed: number): (number, number)
	local t = Config.Training
	local par = t.parFactor * PetLogic.trackPerimeter() / math.max(walkSpeed, 1)
	local bonus = math.clamp(par / math.max(lapTime, 0.1), t.bonusMin, t.bonusMax)
	local reward = math.max(1, math.floor(t.lapBaseReward * trainingMult * bonus + 0.5))
	return reward, bonus
end

function PetLogic.offlineEarnings(income: number, secondsAway: number): number
	if secondsAway < 60 or income <= 0 then
		return 0
	end
	local e = Config.Economy
	return math.floor(income * math.min(secondsAway, e.offlineCapSeconds) * e.offlineRate)
end

-- Fair-play rule: a much faster player can't rob a much slower one.
function PetLogic.canSteal(thiefSpeed: number, victimSpeed: number): boolean
	local s = Config.Steal
	return (victimSpeed + s.fairPlayFloor) * s.fairPlayRatio >= thiefSpeed
end

return PetLogic
