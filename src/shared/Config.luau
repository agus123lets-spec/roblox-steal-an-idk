--!strict
-- Nest Heist: every tunable value lives here so balancing never requires code changes.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Position on the XZ plane around the hub centre (0, 0, 0). 90 degrees points to +Z ("north").
local function polar(angleDegrees: number, distance: number): Vector3
	local a = math.rad(angleDegrees)
	return Vector3.new(math.cos(a) * distance, 0, math.sin(a) * distance)
end

export type RarityInfo = {
	key: string,
	order: number,
	color: Color3,
	spawnWeight: number,
	hatchTime: number,
	feathers: number,
}

export type GuardianInfo = {
	name: string,
	style: string,
	speed: number,
	catchRadius: number,
	noticeDelay: number,
	body: Color3,
	accent: Color3,
}

export type BiomeInfo = {
	key: string,
	name: string,
	icon: string,
	order: number,
	recommendedSpeed: number,
	angle: number,
	distance: number,
	radius: number,
	center: Vector3,
	groundColor: Color3,
	groundMaterial: Enum.Material,
	edgeColor: Color3,
	rockColor: Color3,
	bandColor: Color3,
	nestColor: Color3,
	nestCount: number,
	respawnMin: number,
	respawnMax: number,
	jackpotWeight: number,
	guardian: GuardianInfo,
}

export type PetInfo = {
	key: string,
	name: string,
	biome: string,
	rarity: string,
	income: number,
	shape: string,
	variant: string,
	body: Color3,
	accent: Color3,
}

export type SizeInfo = { key: string, mult: number, scale: number, weight: number }
export type MutationInfo = { key: string, mult: number, chance: number, color: Color3 }
export type ShoeInfo = { name: string, mult: number, cost: number }
export type TrailInfo = { key: string, name: string, cost: number, c1: Color3, c2: Color3 }
export type FeatherItem = { id: string, name: string, desc: string, cost: number, duration: number }

local Config = {}

Config.GameName = "Nest Heist"
Config.polar = polar

---------------------------------------------------------------------------
-- Rarity
---------------------------------------------------------------------------
Config.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

Config.Rarities = {
	Common = { key = "Common", order = 1, color = rgb(205, 210, 220), spawnWeight = 55, hatchTime = 6, feathers = 1 },
	Uncommon = {
		key = "Uncommon",
		order = 2,
		color = rgb(96, 214, 110),
		spawnWeight = 25,
		hatchTime = 10,
		feathers = 2,
	},
	Rare = { key = "Rare", order = 3, color = rgb(70, 160, 255), spawnWeight = 12, hatchTime = 15, feathers = 4 },
	Epic = { key = "Epic", order = 4, color = rgb(186, 96, 255), spawnWeight = 6, hatchTime = 22, feathers = 8 },
	Legendary = {
		key = "Legendary",
		order = 5,
		color = rgb(255, 196, 40),
		spawnWeight = 2,
		hatchTime = 30,
		feathers = 15,
	},
} :: { [string]: RarityInfo }

---------------------------------------------------------------------------
-- World layout
---------------------------------------------------------------------------
Config.Hub = {
	radius = 250,
	plazaRadius = 120,
	groundColor = rgb(124, 204, 102),
	edgeColor = rgb(96, 168, 80),
	rockColor = rgb(118, 98, 84),
	plazaColor = rgb(232, 222, 200),
	plazaTrim = rgb(196, 176, 150),
	spawn = Vector3.new(0, 0, 46),
}

Config.Plots = {
	count = 8,
	ringRadius = 190,
	arcStart = 195,
	arcEnd = 345,
	size = 56,
	startSlots = 6,
	maxSlots = 16,
	colors = {
		rgb(255, 176, 204),
		rgb(255, 200, 146),
		rgb(255, 234, 150),
		rgb(176, 236, 184),
		rgb(156, 212, 255),
		rgb(204, 186, 255),
		rgb(255, 166, 156),
		rgb(150, 226, 220),
	},
	incubatorOffsets = { Vector3.new(-11, 0, -17), Vector3.new(0, 0, -17), Vector3.new(11, 0, -17) },
	pedestalColumns = { -18, -6, 6, 18 },
	pedestalRows = { -6, 4, 14, 24 },
	jogPadOffset = Vector3.new(-22, 0, -21),
	jogPadSize = 8,
	shieldPadOffset = Vector3.new(22.5, 0, -21),
	shieldPadSize = 6,
}

local function biome(info: {
	key: string,
	name: string,
	icon: string,
	order: number,
	recommendedSpeed: number,
	angle: number,
	distance: number,
	groundColor: Color3,
	groundMaterial: Enum.Material,
	edgeColor: Color3,
	rockColor: Color3,
	bandColor: Color3,
	nestColor: Color3,
	respawnMin: number,
	respawnMax: number,
	jackpotWeight: number,
	guardian: GuardianInfo,
}): BiomeInfo
	return {
		key = info.key,
		name = info.name,
		icon = info.icon,
		order = info.order,
		recommendedSpeed = info.recommendedSpeed,
		angle = info.angle,
		distance = info.distance,
		radius = 110,
		center = polar(info.angle, info.distance),
		groundColor = info.groundColor,
		groundMaterial = info.groundMaterial,
		edgeColor = info.edgeColor,
		rockColor = info.rockColor,
		bandColor = info.bandColor,
		nestColor = info.nestColor,
		nestCount = 8,
		respawnMin = info.respawnMin,
		respawnMax = info.respawnMax,
		jackpotWeight = info.jackpotWeight,
		guardian = info.guardian,
	}
end

Config.Biomes = {
	biome({
		key = "Meadow",
		name = "Meadow Hollow",
		icon = "🌼",
		order = 1,
		recommendedSpeed = 0,
		angle = 90,
		distance = 440,
		groundColor = rgb(112, 198, 92),
		groundMaterial = Enum.Material.Grass,
		edgeColor = rgb(88, 162, 72),
		rockColor = rgb(122, 100, 80),
		bandColor = rgb(120, 214, 92),
		nestColor = rgb(150, 108, 70),
		respawnMin = 10,
		respawnMax = 18,
		jackpotWeight = 40,
		guardian = {
			name = "Bramble Boar",
			style = "Boar",
			speed = 14,
			catchRadius = 7,
			noticeDelay = 0.9,
			body = rgb(128, 88, 62),
			accent = rgb(74, 50, 38),
		},
	}),
	biome({
		key = "Candy",
		name = "Candy Cliffs",
		icon = "🍬",
		order = 2,
		recommendedSpeed = 300,
		angle = 55,
		distance = 530,
		groundColor = rgb(255, 186, 216),
		groundMaterial = Enum.Material.SmoothPlastic,
		edgeColor = rgb(242, 142, 192),
		rockColor = rgb(150, 98, 72),
		bandColor = rgb(255, 120, 192),
		nestColor = rgb(170, 110, 80),
		respawnMin = 12,
		respawnMax = 20,
		jackpotWeight = 35,
		guardian = {
			name = "Gummy Golem",
			style = "Golem",
			speed = 36,
			catchRadius = 7.5,
			noticeDelay = 0.7,
			body = rgb(255, 108, 172),
			accent = rgb(255, 236, 120),
		},
	}),
	biome({
		key = "Storm",
		name = "Storm Peaks",
		icon = "⚡",
		order = 3,
		recommendedSpeed = 5000,
		angle = 125,
		distance = 630,
		groundColor = rgb(88, 96, 124),
		groundMaterial = Enum.Material.Slate,
		edgeColor = rgb(62, 68, 92),
		rockColor = rgb(52, 54, 68),
		bandColor = rgb(90, 204, 255),
		nestColor = rgb(96, 90, 104),
		respawnMin = 14,
		respawnMax = 24,
		jackpotWeight = 25,
		guardian = {
			name = "Thunderhorn Ram",
			style = "Ram",
			speed = 58,
			catchRadius = 8,
			noticeDelay = 0.6,
			body = rgb(124, 134, 166),
			accent = rgb(255, 222, 84),
		},
	}),
}

Config.Training = {
	center = Vector3.new(370, 0, 0),
	outerX = 190,
	outerZ = 110,
	innerX = 130,
	innerZ = 50,
	lapBaseReward = 40,
	parFactor = 1.15,
	minTimeFactor = 1.6,
	bonusMin = 0.6,
	bonusMax = 1.6,
	jogRate = 0.5,
}

---------------------------------------------------------------------------
-- Pets: one per rarity in every biome
---------------------------------------------------------------------------
Config.Pets = {
	-- Meadow Hollow
	{
		key = "PebbleBun",
		name = "Pebble Bun",
		biome = "Meadow",
		rarity = "Common",
		income = 1,
		shape = "bunny",
		variant = "",
		body = rgb(178, 162, 148),
		accent = rgb(244, 212, 204),
	},
	{
		key = "CloverChick",
		name = "Clover Chick",
		biome = "Meadow",
		rarity = "Uncommon",
		income = 3,
		shape = "bird",
		variant = "",
		body = rgb(252, 228, 92),
		accent = rgb(112, 202, 92),
	},
	{
		key = "MossyToad",
		name = "Mossy Toad",
		biome = "Meadow",
		rarity = "Rare",
		income = 8,
		shape = "blob",
		variant = "",
		body = rgb(98, 172, 82),
		accent = rgb(204, 238, 124),
	},
	{
		key = "PetalFox",
		name = "Petal Fox",
		biome = "Meadow",
		rarity = "Epic",
		income = 20,
		shape = "critter",
		variant = "fox",
		body = rgb(255, 142, 82),
		accent = rgb(255, 206, 224),
	},
	{
		key = "SunpetalLion",
		name = "Sunpetal Lion",
		biome = "Meadow",
		rarity = "Legendary",
		income = 50,
		shape = "critter",
		variant = "lion",
		body = rgb(255, 208, 92),
		accent = rgb(255, 142, 42),
	},
	-- Candy Cliffs
	{
		key = "GumdropSlime",
		name = "Gumdrop Slime",
		biome = "Candy",
		rarity = "Common",
		income = 40,
		shape = "blob",
		variant = "",
		body = rgb(255, 122, 182),
		accent = rgb(255, 240, 250),
	},
	{
		key = "LolliBird",
		name = "Lolli Bird",
		biome = "Candy",
		rarity = "Uncommon",
		income = 90,
		shape = "bird",
		variant = "",
		body = rgb(255, 250, 252),
		accent = rgb(255, 92, 142),
	},
	{
		key = "TaffyCat",
		name = "Taffy Cat",
		biome = "Candy",
		rarity = "Rare",
		income = 200,
		shape = "critter",
		variant = "cat",
		body = rgb(202, 152, 255),
		accent = rgb(255, 204, 242),
	},
	{
		key = "CocoaBear",
		name = "Cocoa Bear",
		biome = "Candy",
		rarity = "Epic",
		income = 450,
		shape = "critter",
		variant = "bear",
		body = rgb(132, 84, 54),
		accent = rgb(242, 204, 162),
	},
	{
		key = "SprinkleDragon",
		name = "Sprinkle Dragon",
		biome = "Candy",
		rarity = "Legendary",
		income = 1000,
		shape = "dragon",
		variant = "",
		body = rgb(142, 212, 255),
		accent = rgb(255, 152, 212),
	},
	-- Storm Peaks
	{
		key = "StaticMouse",
		name = "Static Mouse",
		biome = "Storm",
		rarity = "Common",
		income = 800,
		shape = "critter",
		variant = "mouse",
		body = rgb(255, 228, 82),
		accent = rgb(92, 92, 112),
	},
	{
		key = "CloudPuff",
		name = "Cloud Puff",
		biome = "Storm",
		rarity = "Uncommon",
		income = 1800,
		shape = "blob",
		variant = "",
		body = rgb(238, 242, 255),
		accent = rgb(152, 202, 255),
	},
	{
		key = "BoltHawk",
		name = "Bolt Hawk",
		biome = "Storm",
		rarity = "Rare",
		income = 4000,
		shape = "bird",
		variant = "",
		body = rgb(72, 112, 202),
		accent = rgb(255, 222, 62),
	},
	{
		key = "ThunderWolf",
		name = "Thunder Wolf",
		biome = "Storm",
		rarity = "Epic",
		income = 9000,
		shape = "critter",
		variant = "wolf",
		body = rgb(62, 72, 112),
		accent = rgb(112, 232, 255),
	},
	{
		key = "TempestDrake",
		name = "Tempest Drake",
		biome = "Storm",
		rarity = "Legendary",
		income = 20000,
		shape = "dragon",
		variant = "",
		body = rgb(112, 62, 172),
		accent = rgb(92, 242, 255),
	},
} :: { PetInfo }

Config.Sizes = {
	{ key = "Tiny", mult = 0.8, scale = 0.8, weight = 20 },
	{ key = "Normal", mult = 1, scale = 1, weight = 56 },
	{ key = "Big", mult = 1.35, scale = 1.25, weight = 17 },
	{ key = "Huge", mult = 2, scale = 1.55, weight = 6 },
	{ key = "Titanic", mult = 3.5, scale = 1.95, weight = 1 },
} :: { SizeInfo }

-- Checked rarest first; luck multiplies each chance.
Config.Mutations = {
	{ key = "Starlight", mult = 4, chance = 0.005, color = rgb(196, 136, 255) },
	{ key = "Diamond", mult = 2.5, chance = 0.02, color = rgb(172, 242, 255) },
	{ key = "Glitter", mult = 1.5, chance = 0.08, color = rgb(255, 230, 120) },
} :: { MutationInfo }

Config.Hatch = {
	luckyBumpChance = 0.08,
}

---------------------------------------------------------------------------
-- Economy & shop
---------------------------------------------------------------------------
Config.Shoes = {
	{ name = "Flip-Flops", mult = 1, cost = 0 },
	{ name = "Sneakers", mult = 2, cost = 50 },
	{ name = "Running Shoes", mult = 4, cost = 300 },
	{ name = "Spring Boots", mult = 8, cost = 1500 },
	{ name = "Jet Sneakers", mult = 16, cost = 8000 },
	{ name = "Storm Striders", mult = 32, cost = 40000 },
	{ name = "Comet Kicks", mult = 64, cost = 200000 },
	{ name = "Nova Boots", mult = 128, cost = 1000000 },
	{ name = "Galaxy Gliders", mult = 256, cost = 5000000 },
	{ name = "Infinity Treads", mult = 512, cost = 25000000 },
} :: { ShoeInfo }

Config.Slots = {
	baseCost = 100,
	growth = 3,
}

Config.Tools = {
	Net = {
		name = "Net Launcher",
		cost = 0,
		cooldown = 3,
		range = 42,
		coneDegrees = 28,
		stun = 1.1,
	},
	Slime = {
		name = "Slime Puddle",
		cost = 2500,
		cooldown = 10,
		range = 36,
		radius = 5.5,
		lifetime = 15,
		slowFactor = 0.45,
		slowDuration = 2.5,
		maxActive = 2,
	},
}

Config.FeatherShop = {
	{ id = "Boost:Luck", name = "Lucky Charm", desc = "2x hatch luck for 10 minutes", cost = 15, duration = 600 },
	{ id = "Boost:Turbo", name = "Turbo Laces", desc = "2x training Speed for 10 minutes", cost = 10, duration = 600 },
} :: { FeatherItem }

Config.Trails = {
	{ key = "Sunburst", name = "Sunburst Trail", cost = 20, c1 = rgb(255, 222, 82), c2 = rgb(255, 122, 62) },
	{ key = "Bubblegum", name = "Bubblegum Trail", cost = 20, c1 = rgb(255, 142, 222), c2 = rgb(162, 122, 255) },
	{ key = "Voltage", name = "Voltage Trail", cost = 35, c1 = rgb(122, 242, 255), c2 = rgb(62, 92, 255) },
} :: { TrailInfo }

Config.Economy = {
	offlineRate = 0.5,
	offlineCapSeconds = 3 * 60 * 60,
	sellSeconds = 60,
}

---------------------------------------------------------------------------
-- Stealing, guardians and events
---------------------------------------------------------------------------
Config.Steal = {
	-- You can't steal from (or net) someone whose Speed is below yours / fairPlayRatio.
	fairPlayRatio = 5,
	fairPlayFloor = 10,
	revengeDuration = 60,
	shieldDuration = 40,
	shieldCooldown = 90,
	grabHold = 0.25,
	stealHold = 1.2,
	droppedLifetime = 20,
	underdogRatio = 2,
	recoverFeathers = 3,
	carryHeight = 4.4,
	guardianStun = 1.4,
	leash = 14,
}

Config.Jackpot = {
	firstDelay = 60,
	interval = 180,
	rarityWeights = { Epic = 70, Legendary = 30 } :: { [string]: number },
	mutationLuck = 5,
}

Config.Movement = {
	baseWalkSpeed = 16,
	walkK = 6,
	walkDivisor = 25,
	maxWalkSpeed = 100,
	jumpHeight = 7.2,
}

Config.Dash = {
	cooldown = 4,
	duration = 0.18,
	factor = 2.4,
	minSpeed = 60,
}

Config.Data = {
	storeName = "NestHeist_v1",
	autosaveInterval = 90,
}

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------
Config.BiomeByKey = {} :: { [string]: BiomeInfo }
for _, info in Config.Biomes do
	Config.BiomeByKey[info.key] = info
end

Config.PetByKey = {} :: { [string]: PetInfo }
for _, info in Config.Pets do
	Config.PetByKey[info.key] = info
end

return Config
