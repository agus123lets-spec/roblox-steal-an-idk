-- Unit tests for game math, config sanity and the generated map. Run: lune run tests/logic.spec
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("../scripts/lib/loader")

local Config = Loader.load("Config")
local PetLogic = Loader.load("PetLogic")
local Format = Loader.load("Format")
local Rng = Loader.load("Rng")
local MapBuilder = Loader.load("MapBuilder")

local passes, failures = 0, 0
local function check(name: string, condition: boolean, detail: any?)
	if condition then
		passes += 1
	else
		failures += 1
		print(`FAIL {name}{if detail ~= nil then ": " .. tostring(detail) else ""}`)
	end
end
local function eq(name: string, actual: any, expected: any)
	check(name, actual == expected, `expected {tostring(expected)}, got {tostring(actual)}`)
end

---------------------------------------------------------------------------
-- Config sanity
---------------------------------------------------------------------------
eq("25 pets", #Config.Pets, 25)
for _, biome in Config.Biomes do
	for _, rarity in Config.RarityOrder do
		local count = 0
		for _, pet in Config.Pets do
			if pet.biome == biome.key and pet.rarity == rarity then
				count += 1
			end
		end
		eq(`one {rarity} pet in {biome.key}`, count, 1)
	end
end
for _, pet in Config.Pets do
	check(`{pet.key}: biome exists`, Config.BiomeByKey[pet.biome] ~= nil)
	check(`{pet.key}: rarity exists`, Config.Rarities[pet.rarity] ~= nil)
	check(`{pet.key}: shape known`, table.find({ "blob", "bunny", "bird", "dragon", "critter" }, pet.shape) ~= nil)
end
for index, key in Config.RarityOrder do
	eq(`rarity order {key}`, Config.Rarities[key].order, index)
end
for i = 2, #Config.Shoes do
	check(`shoes {i}: cost increases`, Config.Shoes[i].cost > Config.Shoes[i - 1].cost)
	check(`shoes {i}: multiplier increases`, Config.Shoes[i].mult > Config.Shoes[i - 1].mult)
end
eq("a pedestal for every slot", #Config.Plots.pedestalColumns * #Config.Plots.pedestalRows, Config.Plots.maxSlots)

-- Speed gates: at a biome's recommended Speed you outrun its guardian; at the previous one you don't.
check("new players outrun the first guardian", PetLogic.walkSpeedFor(0) > Config.Biomes[1].guardian.speed)
for i, biome in Config.Biomes do
	local walk = PetLogic.walkSpeedFor(biome.recommendedSpeed)
	check(
		`{biome.key}: recommended Speed outruns the guardian`,
		walk > biome.guardian.speed,
		`{walk} vs {biome.guardian.speed}`
	)
	if i > 1 then
		local previous = Config.Biomes[i - 1]
		check(`{biome.key}: recommended Speed increases`, biome.recommendedSpeed > previous.recommendedSpeed)
		check(
			`{biome.key}: guardian beats players from the previous biome`,
			PetLogic.walkSpeedFor(previous.recommendedSpeed) < biome.guardian.speed
		)
	end
end

---------------------------------------------------------------------------
-- Walk speed
---------------------------------------------------------------------------
eq("walk speed at 0 Speed", PetLogic.walkSpeedFor(0), 16)
check("walk speed grows with Speed", PetLogic.walkSpeedFor(100) < PetLogic.walkSpeedFor(1000))
eq("walk speed is capped", PetLogic.walkSpeedFor(1e12), Config.Movement.maxWalkSpeed)

---------------------------------------------------------------------------
-- Rolling
---------------------------------------------------------------------------
local rng = Rng.new(2024)
local N = 40000
local counts: { [string]: number } = {}
for _ = 1, N do
	local rarity = PetLogic.rollEggRarity(rng.next, 1)
	counts[rarity] = (counts[rarity] or 0) + 1
end
local totalWeight = 0
for _, key in Config.RarityOrder do
	totalWeight += Config.Rarities[key].spawnWeight
end
for _, key in Config.RarityOrder do
	local expected = Config.Rarities[key].spawnWeight / totalWeight
	local actual = (counts[key] or 0) / N
	check(`{key} spawn rate close to {expected}`, math.abs(actual - expected) < 0.01, actual)
end
local luckyLegendary = 0
for _ = 1, N do
	if PetLogic.rollEggRarity(rng.next, 2) == "Legendary" then
		luckyLegendary += 1
	end
end
check("luck x2 makes Legendary eggs much more common", luckyLegendary > (counts.Legendary or 0) * 2, luckyLegendary)

for _, biome in Config.Biomes do
	for _, rarity in Config.RarityOrder do
		for _ = 1, 50 do
			local kind, size, mutation, lucky = PetLogic.rollHatch(rng.next, biome.key, rarity, 1, false)
			local info = Config.PetByKey[kind]
			local expectedOrder = Config.Rarities[rarity].order + (if lucky then 1 else 0)
			check(`hatch {biome.key}/{rarity}: pet from that biome`, info ~= nil and info.biome == biome.key)
			check(
				`hatch {biome.key}/{rarity}: rarity`,
				info ~= nil and Config.Rarities[info.rarity].order == expectedOrder
			)
			check(`hatch {biome.key}/{rarity}: valid size`, PetLogic.sizeInfo(size) ~= nil)
			check(
				`hatch {biome.key}/{rarity}: valid mutation`,
				mutation == nil or PetLogic.mutationInfo(mutation) ~= nil
			)
		end
	end
end
local normalMutations, jackpotMutations = 0, 0
for _ = 1, 20000 do
	local _, _, m1 = PetLogic.rollHatch(rng.next, "Meadow", "Common", 1, false)
	local _, _, m2 = PetLogic.rollHatch(rng.next, "Meadow", "Common", 1, true)
	if m1 then
		normalMutations += 1
	end
	if m2 then
		jackpotMutations += 1
	end
end
check(
	"jackpot eggs mutate far more often",
	jackpotMutations > normalMutations * 3,
	`{normalMutations} vs {jackpotMutations}`
)
for _ = 1, 200 do
	check(
		"jackpot rarity is Epic or Legendary",
		table.find({ "Epic", "Legendary" }, PetLogic.rollJackpotRarity(rng.next)) ~= nil
	)
end

---------------------------------------------------------------------------
-- Economy
---------------------------------------------------------------------------
local drake = { id = "a", kind = "TempestDrake", size = "Huge", mutation = "Starlight" }
eq("income = base x size x mutation", PetLogic.income(drake), 20000 * 2 * 4)
eq("sell value = 60s of income", PetLogic.sellValue(drake), 20000 * 2 * 4 * 60)
eq("describe", PetLogic.describe(drake), "Huge Starlight Tempest Drake")
eq("describe plain", PetLogic.describe({ id = "b", kind = "PebbleBun", size = "Normal" }), "Pebble Bun")
eq("unknown pet earns nothing", PetLogic.income({ id = "c", kind = "Nope", size = "Normal" }), 0)
eq("7th slot costs 100", PetLogic.slotCost(6), 100)
eq("8th slot costs 300", PetLogic.slotCost(7), 300)
eq("no slots past the max", PetLogic.slotCost(Config.Plots.maxSlots), nil)
eq("no offline earnings under a minute", PetLogic.offlineEarnings(100, 30), 0)
eq("offline earnings at half rate", PetLogic.offlineEarnings(100, 600), 30000)
eq("offline earnings capped at 3h", PetLogic.offlineEarnings(100, 10 * 3600), 100 * 3 * 3600 * 0.5)

---------------------------------------------------------------------------
-- Training
---------------------------------------------------------------------------
for _, speed in { 0, 300, 5000, 100000 } do
	local walk = PetLogic.walkSpeedFor(speed)
	local centerLap = PetLogic.trackPerimeter() / walk
	local tightLap = 2 * (Config.Training.innerX + Config.Training.innerZ) / walk
	check(`honest lap accepted at Speed {speed}`, centerLap > PetLogic.minLapTime(walk))
	check(`infield-hugging lap accepted at Speed {speed}`, tightLap > PetLogic.minLapTime(walk))
	local reward, bonus = PetLogic.lapReward(1, centerLap, walk)
	check(
		`lap bonus in range at Speed {speed}`,
		bonus >= Config.Training.bonusMin and bonus <= Config.Training.bonusMax,
		bonus
	)
	check(`lap reward positive at Speed {speed}`, reward >= 1)
end
check("faster laps pay more", PetLogic.lapReward(1, 10, 16) > PetLogic.lapReward(1, 1000, 16))

---------------------------------------------------------------------------
-- Fair play
---------------------------------------------------------------------------
check("equal players can steal", PetLogic.canSteal(1000, 1000))
check("underdogs can rob pros", PetLogic.canSteal(10, 100000))
check("pros can't rob newbies", not PetLogic.canSteal(100000, 10))
check("two newbies can rob each other", PetLogic.canSteal(20, 0))

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
local formatCases: { { number | string } } = {
	{ 0, "0" },
	{ 999, "999" },
	{ 1000, "1K" },
	{ 1234, "1.23K" },
	{ 10000, "10K" },
	{ 999999, "999K" },
	{ 1e6, "1M" },
	{ 1050000, "1.05M" },
	{ 45600000, "45.6M" },
	{ 1e15, "1Qa" },
	{ 1.5, "1.5" },
	{ 100.5, "100" },
	{ -2500, "-2.5K" },
}
for _, case in formatCases do
	eq(`Format.short({case[1]})`, Format.short(case[1] :: number), case[2])
end
eq("Format.money", Format.money(12345), "$12.3K")
eq("Format.clock", Format.clock(65), "1:05")
eq("Format.clock negative", Format.clock(-3), "0:00")

---------------------------------------------------------------------------
-- Map
---------------------------------------------------------------------------
local map = MapBuilder.build()
local plots = map:FindFirstChild("Plots")
eq("8 plots", #plots:GetChildren(), Config.Plots.count)
local floors = {}
for _, plot in plots:GetChildren() do
	for _, name in { "Floor", "Incubators", "Pedestals", "JogPad", "ShieldPad", "ShieldDome", "Pets", "SignBoard" } do
		check(`{plot.Name} has {name}`, plot:FindFirstChild(name) ~= nil)
	end
	check(`{plot.Name} has PlotIndex`, type(plot:GetAttribute("PlotIndex")) == "number")
	check(`{plot.Name} has an owner label`, plot:FindFirstChild("OwnerLabel", true) ~= nil)
	eq(`{plot.Name} incubators`, #plot.Incubators:GetChildren(), #Config.Plots.incubatorOffsets)
	for _, incubator in plot.Incubators:GetChildren() do
		check(`{plot.Name}.{incubator.Name} has a Spot`, incubator:FindFirstChild("Spot") ~= nil)
		check(`{plot.Name}.{incubator.Name} has a Status label`, incubator:FindFirstChild("Status", true) ~= nil)
	end
	eq(`{plot.Name} pedestals`, #plot.Pedestals:GetChildren(), Config.Plots.maxSlots)
	for _, pedestal in plot.Pedestals:GetChildren() do
		check(`{plot.Name}.{pedestal.Name} has a Spot`, pedestal:FindFirstChild("Spot") ~= nil)
	end
	check(`{plot.Name} shield pad has a Status label`, plot.ShieldPad:FindFirstChild("Status", true) ~= nil)
	table.insert(floors, plot.Floor)
end

-- Plots stay on the hub and never overlap each other.
for _, floor in floors do
	local half = floor.Size.X / 2
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local corner = floor.CFrame:PointToWorldSpace(roblox.Vector3.new(sx * half, 0, sz * half))
			local radius = math.sqrt(corner.X ^ 2 + corner.Z ^ 2)
			check(`{floor.Parent.Name} corner on the hub`, radius < Config.Hub.radius - 2, radius)
			for _, other in floors do
				if other ~= floor then
					local localPos = other.CFrame:PointToObjectSpace(corner)
					local inside = math.abs(localPos.X) < other.Size.X / 2 and math.abs(localPos.Z) < other.Size.Z / 2
					check(`{floor.Parent.Name} does not overlap {other.Parent.Name}`, not inside)
				end
			end
		end
	end
end

local biomes = map:FindFirstChild("Biomes")
eq("3 biomes", #biomes:GetChildren(), #Config.Biomes)
for _, biome in Config.Biomes do
	local model = biomes:FindFirstChild(biome.key)
	check(`{biome.key} built`, model ~= nil)
	local nests = model:FindFirstChild("Nests"):GetChildren()
	eq(`{biome.key} nests`, #nests, biome.nestCount)
	for i, nest in nests do
		local spot = nest:FindFirstChild("Spot")
		check(`{biome.key}.{nest.Name} has a Spot`, spot ~= nil)
		local offset = spot.CFrame.Position - biome.center
		local distance = math.sqrt(offset.X ^ 2 + offset.Z ^ 2)
		check(`{biome.key}.{nest.Name} is on the island`, distance < biome.radius - 15, distance)
		for j, other in nests do
			if j > i then
				local d = (other:FindFirstChild("Spot").CFrame.Position - spot.CFrame.Position).Magnitude
				check(`{biome.key} nests {i} and {j} apart`, d > 10, d)
			end
		end
	end
	local guardian = model:FindFirstChild("Guardian")
	check(`{biome.key} guardian has a PrimaryPart`, guardian ~= nil and guardian.PrimaryPart ~= nil)
	local eyes = 0
	for _, part in guardian:GetDescendants() do
		if part.Name == "Eye" then
			eyes += 1
		end
	end
	eq(`{biome.key} guardian has two eyes`, eyes, 2)
	check(`{biome.key} guardian has a StateLabel`, guardian:FindFirstChild("StateLabel", true) ~= nil)
	check(`{biome.key} bridge built`, map.Bridges:FindFirstChild(biome.key .. "Bridge") ~= nil)
end
check("training track built", map:FindFirstChild("Training") ~= nil and map.Training:FindFirstChild("Infield") ~= nil)
check("training bridge built", map:FindFirstChild("TrainingBridge") ~= nil)
check("spawn built", map.Hub:FindFirstChild("Spawn") ~= nil and map.Hub.Spawn.ClassName == "SpawnLocation")
local unanchored = 0
for _, descendant in map:GetDescendants() do
	if descendant:IsA("BasePart") and not descendant.Anchored then
		unanchored += 1
	end
end
eq("every map part is anchored", unanchored, 0)

---------------------------------------------------------------------------
-- World layout for the new islands
---------------------------------------------------------------------------
local T = Config.Training
for i, a in Config.Biomes do
	local fromHub = math.sqrt(a.center.X ^ 2 + a.center.Z ^ 2)
	check(`{a.key} island clear of the hub`, fromHub - a.radius > Config.Hub.radius + 20, fromHub)
	for j, b in Config.Biomes do
		if j > i then
			local d = (a.center - b.center).Magnitude
			check(`{a.key} and {b.key} islands apart`, d > a.radius + b.radius + 20, d)
		end
	end
	local nearestX = math.clamp(a.center.X, T.center.X - T.outerX / 2 - 5, T.center.X + T.outerX / 2 + 5)
	local nearestZ = math.clamp(a.center.Z, T.center.Z - T.outerZ / 2 - 5, T.center.Z + T.outerZ / 2 + 5)
	local gap = math.sqrt((a.center.X - nearestX) ^ 2 + (a.center.Z - nearestZ) ^ 2)
	check(`{a.key} island clear of the training track`, gap > a.radius + 10, gap)

	-- Its bridge must not cut through another island or the training track.
	local from = Config.polar(a.angle, Config.Hub.radius)
	local to = Config.polar(a.angle, a.distance - a.radius)
	local along = to - from
	for _, b in Config.Biomes do
		if b ~= a then
			local t = math.clamp((b.center - from):Dot(along) / along:Dot(along), 0, 1)
			local closest = from + along * t
			check(`{a.key} bridge clear of {b.key}`, (b.center - closest).Magnitude > b.radius + 12)
		end
	end
	for step = 0, 40 do
		local p = from + along * (step / 40)
		local insideTrack = math.abs(p.X - T.center.X) < T.outerX / 2 + 16
			and math.abs(p.Z - T.center.Z) < T.outerZ / 2 + 16
		check(`{a.key} bridge clear of the training track`, not insideTrack)
	end
end
local pathAngles = { 0 }
for _, biome in Config.Biomes do
	table.insert(pathAngles, biome.angle)
end
for _, child in map.Hub:GetChildren() do
	if child.Name == "Tree" then
		local p = child:FindFirstChild("Trunk").CFrame.Position
		for _, angle in pathAngles do
			local dir = Config.polar(angle, 1)
			local forward = p.X * dir.X + p.Z * dir.Z
			local side = math.abs(p.X * dir.Z - p.Z * dir.X)
			check(`hub tree clear of the {angle} degree path`, forward < 0 or side > 17, side)
		end
	end
end
local boards = map.Hub:FindFirstChild("Leaderboards")
eq("leaderboards built", if boards then #boards:GetChildren() else 0, #Config.Leaderboards.boards)
for _, info in Config.Leaderboards.boards do
	local board = boards:FindFirstChild(info.key):FindFirstChild("Board")
	for _, faceName in { "Front", "Back" } do
		local gui = board:FindFirstChild(faceName)
		check(`{info.key} {faceName} face`, gui ~= nil and gui.ClassName == "SurfaceGui")
		for i = 1, 10 do
			check(`{info.key} {faceName} row {i}`, gui:FindFirstChild("Row" .. i) ~= nil)
		end
		check(`{info.key} {faceName} status`, gui:FindFirstChild("Status") ~= nil)
	end
end

---------------------------------------------------------------------------
-- Progression
---------------------------------------------------------------------------
local Progression = Loader.load("Progression")

local c0, s0 = Progression.rebirthRequirement(0)
local c1, s1 = Progression.rebirthRequirement(1)
eq("first rebirth coins", c0, Config.Rebirth.baseCoins)
eq("first rebirth Speed", s0, Config.Rebirth.baseSpeed)
check("rebirths get harder", c1 > c0 and s1 > s0)
check("first rebirth needs Storm Peaks Speed", s0 >= Config.BiomeByKey.Storm.recommendedSpeed)
eq("rebirth income multiplier", Progression.rebirthIncomeMultiplier(2), 1 + 2 * Config.Rebirth.incomeBonus)
eq("rebirth training multiplier", Progression.rebirthTrainingMultiplier(4), 1 + 4 * Config.Rebirth.trainingBonus)

local index: { [string]: boolean } = {}
eq("no biomes complete", Progression.completedBiomes(index), 0)
for _, info in Config.Pets do
	if info.biome == "Meadow" then
		index[info.key] = true
	end
end
check("Meadow complete", Progression.biomeComplete(index, "Meadow"))
check("Candy not complete", not Progression.biomeComplete(index, "Candy"))
eq("one biome complete", Progression.completedBiomes(index), 1)
eq("five pets discovered", Progression.discovered(index), 5)
eq("Index bonus", Progression.incomeMultiplier(0, index, 0), 1 + Config.Index.biomeBonus)
eq(
	"friend bonus is capped",
	Progression.friendMultiplier(10),
	1 + Config.Friends.bonusPerFriend * Config.Friends.maxFriends
)
local stacked = (1 + 2 * Config.Rebirth.incomeBonus)
	* (1 + Config.Index.biomeBonus)
	* (1 + Config.Friends.bonusPerFriend)
check("income boosts stack", math.abs(Progression.incomeMultiplier(2, index, 1) - stacked) < 1e-9)

local function makePet(id: string, kind: string, size: string, mutation: string?)
	return { id = id, kind = kind, size = size, mutation = mutation }
end
local pets = {
	makePet("a", "PebbleBun", "Huge"),
	makePet("b", "PebbleBun", "Normal"),
	makePet("c", "PebbleBun", "Tiny", "Glitter"),
	makePet("d", "PebbleBun", "Normal"),
	makePet("e", "CloverChick", "Normal"),
}
local selection = Progression.fuseSelection(pets, "PebbleBun")
check("fusion uses three pets", selection ~= nil and #selection == 3)
local used = {}
for _, p in selection or {} do
	used[p.id] = true
end
check("fusion keeps your best copy", not used.a and used.b and used.c and used.d)
local fusedKind, fusedSize, fusedMutation = Progression.fuseResult(selection)
eq("fusion makes the next rarity", fusedKind, "CloverChick")
eq("fusion keeps the best size", fusedSize, "Normal")
eq("fusion keeps the best mutation", fusedMutation, "Glitter")
check("fusion needs three of a kind", Progression.fuseSelection(pets, "CloverChick") == nil)
local lionKind, lionSize = Progression.fuseResult({
	makePet("x", "SunpetalLion", "Big"),
	makePet("y", "SunpetalLion", "Normal"),
	makePet("z", "SunpetalLion", "Normal"),
})
eq("legendary fusion keeps the pet", lionKind, "SunpetalLion")
eq("legendary fusion grows a size", lionSize, "Huge")
local titanKind = Progression.fuseResult({
	makePet("x", "SunpetalLion", "Titanic"),
	makePet("y", "SunpetalLion", "Normal"),
	makePet("z", "SunpetalLion", "Normal"),
})
eq("titanic legendaries can't fuse", titanKind, nil)
for _, info in Config.Pets do
	if Config.Rarities[info.rarity].order < #Config.RarityOrder then
		local resultKind = Progression.fuseResult({
			makePet("1", info.key, "Normal"),
			makePet("2", info.key, "Normal"),
			makePet("3", info.key, "Normal"),
		})
		local result = if resultKind then Config.PetByKey[resultKind] else nil
		check(
			`{info.key} fuses into the next rarity of its biome`,
			result ~= nil
				and result.biome == info.biome
				and Config.Rarities[result.rarity].order == Config.Rarities[info.rarity].order + 1
		)
	end
end

check("first daily claim", Progression.canClaimDaily(0, 1000))
check("daily cooldown", not Progression.canClaimDaily(1000, 1000 + Config.Daily.cooldown - 1))
check("daily ready again", Progression.canClaimDaily(1000, 1000 + Config.Daily.cooldown))
eq("streak continues", Progression.nextStreak(1000, 3, 1000 + Config.Daily.cooldown + 60), 4)
eq("streak resets after the window", Progression.nextStreak(1000, 3, 1000 + Config.Daily.streakWindow + 1), 1)
eq("first streak", Progression.nextStreak(0, 0, 5000), 1)
check("daily rewards repeat weekly", Progression.dailyReward(#Config.Daily.rewards + 1) == Progression.dailyReward(1))
eq("daily coins have a minimum", Progression.dailyCoins(Config.Daily.rewards[1], 0), Config.Daily.rewards[1].minCoins)
eq(
	"daily coins scale with income",
	Progression.dailyCoins(Config.Daily.rewards[1], 1000),
	1000 * Config.Daily.rewards[1].coinsSeconds
)
eq("feather days pay no coins", Progression.dailyCoins(Config.Daily.rewards[2], 1000), 0)

for _, userId in { 1, 42, 123456789, 9876543210 } do
	for day = 20000, 20013 do
		local quests = Progression.generateQuests(userId, day)
		eq(`{Config.Quests.perDay} quests for {userId}/{day}`, #quests, Config.Quests.perDay)
		local seen, pvp = {}, 0
		for _, quest in quests do
			local info = Progression.questInfo(quest.id)
			check(`quest {quest.id} is known`, info ~= nil)
			check(`quest {quest.id} appears once`, not seen[quest.id])
			seen[quest.id] = true
			if info then
				pvp += if info.pvp then 1 else 0
				check(`quest {quest.id} target in range`, quest.target >= info.min and quest.target <= info.max)
			end
			check(`quest {quest.id} pays feathers`, quest.feathers > 0 and quest.progress == 0 and not quest.claimed)
			check(`quest {quest.id} has text`, #Progression.questText(quest.id, quest.target) > 8)
		end
		check(`at most one PvP quest for {userId}/{day}`, pvp <= 1)
		local again = Progression.generateQuests(userId, day)
		check(
			`quests are stable for {userId}/{day}`,
			again[1].id == quests[1].id and again[3].target == quests[3].target
		)
	end
end
eq("quest day", Progression.questDay(86400 * 3 + 5), 3)
eq("singular quest text", Progression.questText("Steal", 1), "Steal an egg from another player")
eq("plural quest text", Progression.questText("Hatch", 4), "Hatch 4 eggs")

eq("codes are normalised", Progression.normalizeCode(" nest heist "), "NESTHEIST")
for code in Config.Codes do
	eq(`code {code} is stored normalised`, Progression.normalizeCode(code), code)
end
for _, theme in Config.Themes do
	check(`theme {theme.key} costs feathers`, theme.cost > 0 and theme.key ~= "Classic")
end
local knownEffects =
	{ luck = true, income = true, training = true, eggLuck = true, respawn = true, guardianSpeed = true }
for _, event in Config.Events.list do
	check(`event {event.key} ends before the next one`, event.duration < Config.Events.interval)
	for effect in event.effects do
		check(`event {event.key} effect {effect} is wired up`, knownEffects[effect] == true)
	end
end
eq("Format.duration hours", Format.duration(3725), "1h 2m")
eq("Format.duration minutes", Format.duration(125), "2m 5s")
eq("Format.duration seconds", Format.duration(9), "9s")

print(`logic.spec: {passes} passed, {failures} failed`)
if failures > 0 then
	process.exit(1)
end
