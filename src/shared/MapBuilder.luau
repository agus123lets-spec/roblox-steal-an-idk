--!strict
-- Builds the whole world from Config. Runs at build time under Lune (to bake the map into the
-- place file, so it is visible and editable in Studio) and at runtime if Workspace.Map is missing.

local Config = require(script.Parent.Config)
local Builders = require(script.Parent.Builders)
local Rng = require(script.Parent.Rng)

local MapBuilder = {}

local block = Builders.block
local ball = Builders.ball
local ellipsoid = Builders.ellipsoid
local cylinder = Builders.cylinder
local noCollide = Builders.noCollide

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function newModel(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Vertical disc whose top surface sits at topY.
local function disc(
	parent: Instance,
	name: string,
	radius: number,
	thickness: number,
	center: Vector3,
	topY: number,
	color: Color3,
	material: Enum.Material
): Part
	return cylinder(
		parent,
		name,
		thickness,
		radius * 2,
		CFrame.new(center.X, topY - thickness / 2, center.Z),
		color,
		material
	)
end

local function floatingIsland(
	parent: Instance,
	center: Vector3,
	radius: number,
	top: Color3,
	topMaterial: Enum.Material,
	edge: Color3,
	rock: Color3
)
	disc(parent, "Ground", radius, 4, center, 0, top, topMaterial)
	disc(parent, "Edge", radius + 2.5, 3, center, -1.5, edge, Enum.Material.SmoothPlastic)
	disc(parent, "Rock", radius * 0.88, 12, center, -3, rock, Enum.Material.Rock)
	disc(parent, "Rock", radius * 0.62, 16, center, -14, rock:Lerp(BLACK, 0.12), Enum.Material.Rock)
	disc(parent, "Rock", radius * 0.32, 18, center, -28, rock:Lerp(BLACK, 0.25), Enum.Material.Rock)
end

local function sign(
	adornee: BasePart,
	title: string,
	subtitle: string?,
	color: Color3,
	offset: Vector3,
	widthStuds: number,
	maxDistance: number
): BillboardGui
	local height = if subtitle then widthStuds * 0.3 else widthStuds * 0.18
	local gui = Builders.billboard(adornee, offset, UDim2.fromScale(widthStuds, height), maxDistance)
	Builders.text(
		gui,
		"Title",
		title,
		UDim2.fromScale(1, if subtitle then 0.6 else 1),
		UDim2.fromScale(0, 0),
		color,
		Enum.Font.FredokaOne
	)
	if subtitle then
		Builders.text(
			gui,
			"Subtitle",
			subtitle,
			UDim2.fromScale(1, 0.38),
			UDim2.fromScale(0, 0.62),
			WHITE,
			Enum.Font.GothamBold
		)
	end
	return gui
end

local function tree(parent: Instance, position: Vector3, scale: number, leaf: Color3)
	local m = newModel(parent, "Tree")
	cylinder(
		m,
		"Trunk",
		8 * scale,
		1.6 * scale,
		CFrame.new(position + Vector3.new(0, 4 * scale, 0)),
		Color3.fromRGB(120, 84, 58),
		Enum.Material.Wood
	)
	ball(m, "Leaves", 8 * scale, CFrame.new(position + Vector3.new(0, 9 * scale, 0)), leaf, Enum.Material.Grass)
	ball(
		m,
		"Leaves",
		6 * scale,
		CFrame.new(position + Vector3.new(2.2 * scale, 7.6 * scale, 1.2 * scale)),
		leaf:Lerp(WHITE, 0.08),
		Enum.Material.Grass
	)
	ball(
		m,
		"Leaves",
		5.5 * scale,
		CFrame.new(position + Vector3.new(-2 * scale, 7.8 * scale, -1.4 * scale)),
		leaf:Lerp(BLACK, 0.08),
		Enum.Material.Grass
	)
end

local function lamp(parent: Instance, position: Vector3, color: Color3)
	local m = newModel(parent, "Lamp")
	cylinder(
		m,
		"Pole",
		12,
		0.8,
		CFrame.new(position + Vector3.new(0, 6, 0)),
		Color3.fromRGB(60, 62, 78),
		Enum.Material.Metal
	)
	local bulb = ball(m, "Bulb", 2.2, CFrame.new(position + Vector3.new(0, 12.6, 0)), color, Enum.Material.Neon)
	noCollide(bulb)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 22
	light.Brightness = 1.4
	light.Parent = bulb
end

---------------------------------------------------------------------------
-- Hub
---------------------------------------------------------------------------
local function buildHub(map: Instance)
	local hub = folder(map, "Hub")
	local H = Config.Hub
	floatingIsland(hub, Vector3.zero, H.radius, H.groundColor, Enum.Material.Grass, H.edgeColor, H.rockColor)
	disc(hub, "PlazaTrim", H.plazaRadius + 3, 0.4, Vector3.zero, 0.2, H.plazaTrim, Enum.Material.SmoothPlastic)
	disc(hub, "Plaza", H.plazaRadius, 0.6, Vector3.zero, 0.3, H.plazaColor, Enum.Material.Pavement)

	-- Stone paths from the plaza to every bridge.
	local pathAngles = { 0 }
	for _, biome in Config.Biomes do
		table.insert(pathAngles, biome.angle)
	end
	for _, angle in pathAngles do
		local from = Config.polar(angle, H.plazaRadius - 2)
		local to = Config.polar(angle, H.radius - 1)
		local mid = (from + to) / 2
		block(
			hub,
			"Path",
			Vector3.new(22, 0.6, (to - from).Magnitude),
			CFrame.lookAt(mid, to) * CFrame.new(0, -0.06, 0), -- just under the plaza to avoid z-fighting
			H.plazaColor:Lerp(BLACK, 0.06),
			Enum.Material.Pavement
		)
	end

	-- Fountain with the golden egg statue.
	local fountain = newModel(hub, "Fountain")
	local stone = Color3.fromRGB(236, 232, 224)
	local water = Color3.fromRGB(110, 200, 255)
	cylinder(fountain, "Basin", 2.4, 22, CFrame.new(0, 1.5, 0), stone, Enum.Material.Marble)
	local pool = cylinder(fountain, "Water", 0.4, 19.5, CFrame.new(0, 2.6, 0), water, Enum.Material.Glass)
	pool.Transparency = 0.25
	cylinder(fountain, "Pillar", 7, 2.6, CFrame.new(0, 5.5, 0), stone, Enum.Material.Marble)
	cylinder(fountain, "Bowl", 1.2, 8, CFrame.new(0, 8.6, 0), stone, Enum.Material.Marble)
	local statue = ellipsoid(
		fountain,
		"GoldenEgg",
		Vector3.new(4.4, 5.6, 4.4),
		CFrame.new(0, 12.2, 0),
		Color3.fromRGB(255, 204, 60),
		Enum.Material.Neon
	)
	sign(
		statue,
		string.upper(Config.GameName),
		"Grab eggs • Escape guardians • Hatch pets!",
		Color3.fromRGB(255, 214, 90),
		Vector3.new(0, 10, 0),
		44,
		400
	)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(14, 1.2, 14)
	spawn.CFrame = CFrame.new(H.spawn + Vector3.new(0, 0.3, 0))
	spawn.Color = Color3.fromRGB(255, 214, 120)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Parent = hub

	for i = 0, 7 do
		lamp(
			hub,
			Config.polar(22.5 + i * 45, H.plazaRadius - 6) + Vector3.new(0, 0.3, 0),
			Color3.fromRGB(255, 226, 160)
		)
	end

	local rng = Rng.new(99)
	local treeAngles = { 35, 43, 70, 76, 106, 112, 142, 148, 172 }
	for _, angle in treeAngles do
		local position = Config.polar(angle + rng.range(-3, 3), H.radius - rng.range(14, 30))
		tree(hub, position, rng.range(0.9, 1.3), Color3.fromRGB(96, 176, 80))
	end

	-- Signposts at each bridge.
	for _, biome in Config.Biomes do
		local dir = Config.polar(biome.angle, 1)
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local position = Config.polar(biome.angle, H.radius - 18) + side * 16
		local post = block(
			hub,
			"Signpost",
			Vector3.new(1.2, 9, 1.2),
			CFrame.new(position + Vector3.new(0, 4.5, 0)),
			Color3.fromRGB(120, 84, 58),
			Enum.Material.Wood
		)
		local subtitle = if biome.recommendedSpeed > 0
			then `Recommended Speed: {biome.recommendedSpeed}+`
			else "Perfect for beginners!"
		sign(
			post,
			`{biome.icon} {biome.name}`,
			subtitle,
			biome.bandColor:Lerp(WHITE, 0.3),
			Vector3.new(0, 8, 0),
			26,
			250
		)
	end
	local trainingPost = block(
		hub,
		"Signpost",
		Vector3.new(1.2, 9, 1.2),
		CFrame.new(H.radius - 18, 4.5, 16),
		Color3.fromRGB(120, 84, 58),
		Enum.Material.Wood
	)
	sign(
		trainingPost,
		"🏃 Training Track",
		"Run laps to gain Speed",
		Color3.fromRGB(255, 160, 120),
		Vector3.new(0, 8, 0),
		26,
		250
	)
end

---------------------------------------------------------------------------
-- Player plots ("nests")
---------------------------------------------------------------------------
local function buildPlot(parent: Instance, index: number)
	local P = Config.Plots
	local angle = P.arcStart + (index - 1) * (P.arcEnd - P.arcStart) / (P.count - 1)
	local center = Config.polar(angle, P.ringRadius)
	local cf = CFrame.lookAt(center, Vector3.zero) -- -Z (front) faces the hub
	local color = P.colors[index]
	local half = P.size / 2
	local trim = color:Lerp(BLACK, 0.25)

	local plot = newModel(parent, "Plot" .. index)
	plot:SetAttribute("PlotIndex", index)
	block(plot, "Floor", Vector3.new(P.size, 1, P.size), cf * CFrame.new(0, 0.5, 0), color, Enum.Material.SmoothPlastic)

	-- Low fence with an opening at the front.
	local railHeight = 1.6
	block(plot, "Rail", Vector3.new(P.size, railHeight, 1), cf * CFrame.new(0, 1 + railHeight / 2, half - 0.5), trim)
	for _, side in { -1, 1 } do
		block(
			plot,
			"Rail",
			Vector3.new(1, railHeight, P.size),
			cf * CFrame.new(side * (half - 0.5), 1 + railHeight / 2, 0),
			trim
		)
		block(
			plot,
			"Rail",
			Vector3.new(18, railHeight, 1),
			cf * CFrame.new(side * (half - 9), 1 + railHeight / 2, -half + 0.5),
			trim
		)
	end

	-- Incubators where carried eggs hatch.
	local incubators = folder(plot, "Incubators")
	for i, offset in P.incubatorOffsets do
		local inc = newModel(incubators, "Incubator" .. i)
		inc:SetAttribute("Index", i)
		local base = cf * CFrame.new(offset)
		cylinder(inc, "Base", 2, 6, base * CFrame.new(0, 2, 0), Color3.fromRGB(200, 206, 222), Enum.Material.Metal)
		local ring = cylinder(inc, "Ring", 0.4, 6.4, base * CFrame.new(0, 3.1, 0), color, Enum.Material.Neon)
		noCollide(ring)
		local dome =
			ball(inc, "Dome", 5.6, base * CFrame.new(0, 4.6, 0), Color3.fromRGB(205, 240, 255), Enum.Material.Glass)
		dome.Transparency = 0.7
		dome.CastShadow = false
		noCollide(dome)
		local spot = block(inc, "Spot", Vector3.new(1, 1, 1), base * CFrame.new(0, 4.7, 0), WHITE)
		spot.Transparency = 1
		noCollide(spot)
		local gui = Builders.billboard(spot, Vector3.new(0, 4.2, 0), UDim2.fromScale(7, 1.6), 90)
		Builders.text(gui, "Status", "Empty", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), WHITE, Enum.Font.FredokaOne)
	end

	-- Pet pedestals (4x4); the server shows only the unlocked ones as solid.
	local pedestals = folder(plot, "Pedestals")
	local n = 0
	for _, z in P.pedestalRows do
		for _, x in P.pedestalColumns do
			n += 1
			local pedestal = cylinder(
				pedestals,
				"Pedestal" .. n,
				1.2,
				7,
				cf * CFrame.new(x, 1.6, z),
				WHITE,
				Enum.Material.SmoothPlastic
			)
			pedestal:SetAttribute("SlotIndex", n)
			local spot = block(pedestal, "Spot", Vector3.new(1, 1, 1), cf * CFrame.new(x, 2.2, z), WHITE)
			spot.Transparency = 1
			noCollide(spot)
		end
	end

	-- Jog pad (idle training) and shield pad.
	local jog = block(
		plot,
		"JogPad",
		Vector3.new(P.jogPadSize, 0.4, P.jogPadSize),
		cf * CFrame.new(P.jogPadOffset + Vector3.new(0, 1.2, 0)),
		Color3.fromRGB(90, 220, 200),
		Enum.Material.SmoothPlastic
	)
	local jogBorder = block(
		plot,
		"JogBorder",
		Vector3.new(P.jogPadSize + 1, 0.3, P.jogPadSize + 1),
		cf * CFrame.new(P.jogPadOffset + Vector3.new(0, 1.1, 0)),
		Color3.fromRGB(40, 140, 130),
		Enum.Material.Neon
	)
	noCollide(jogBorder)
	sign(
		jog,
		"🏃 Jog Pad",
		"Stand here to train while AFK",
		Color3.fromRGB(140, 255, 230),
		Vector3.new(0, 5, 0),
		9,
		60
	)

	local shield = block(
		plot,
		"ShieldPad",
		Vector3.new(P.shieldPadSize, 0.5, P.shieldPadSize),
		cf * CFrame.new(P.shieldPadOffset + Vector3.new(0, 1.25, 0)),
		Color3.fromRGB(90, 150, 255),
		Enum.Material.Neon
	)
	local shieldGui = Builders.billboard(shield, Vector3.new(0, 5, 0), UDim2.fromScale(9, 2.6), 70)
	Builders.text(
		shieldGui,
		"Title",
		"🛡 Shield",
		UDim2.fromScale(1, 0.55),
		UDim2.fromScale(0, 0),
		Color3.fromRGB(170, 210, 255),
		Enum.Font.FredokaOne
	)
	Builders.text(
		shieldGui,
		"Status",
		"Step here to protect your eggs",
		UDim2.fromScale(1, 0.45),
		UDim2.fromScale(0, 0.55),
		WHITE,
		Enum.Font.GothamBold
	)

	local dome = ball(plot, "ShieldDome", P.size * 1.48, cf, Color3.fromRGB(120, 180, 255), Enum.Material.ForceField)
	dome.Transparency = 1
	dome.CastShadow = false
	noCollide(dome)

	-- Owner sign at the back.
	block(
		plot,
		"SignPost",
		Vector3.new(1.2, 10, 1.2),
		cf * CFrame.new(0, 6, half - 1.5),
		Color3.fromRGB(120, 84, 58),
		Enum.Material.Wood
	)
	local board =
		block(plot, "SignBoard", Vector3.new(14, 4, 0.8), cf * CFrame.new(0, 10.5, half - 1.5), trim:Lerp(WHITE, 0.2))
	local ownerGui = Builders.billboard(board, Vector3.new(0, 4.5, 0), UDim2.fromScale(22, 4.5), 300)
	ownerGui.Name = "OwnerGui"
	Builders.text(
		ownerGui,
		"OwnerLabel",
		"Empty Nest",
		UDim2.fromScale(1, 1),
		UDim2.fromScale(0, 0),
		color:Lerp(WHITE, 0.35),
		Enum.Font.FredokaOne
	)

	folder(plot, "Pets")
end

---------------------------------------------------------------------------
-- Biomes
---------------------------------------------------------------------------
local function decorate(parent: Instance, biome: Config.BiomeInfo, rng: Rng.Rng, avoid: { Vector3 }, toHub: Vector3)
	local decor = folder(parent, "Decor")
	local center = biome.center

	local function freeSpot(minR: number, maxR: number, clearance: number): Vector3?
		for _ = 1, 25 do
			local a = rng.range(0, math.pi * 2)
			local r = rng.range(minR, maxR)
			local offset = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			local ok = r > 18
			if offset.Unit:Dot(toHub) > math.cos(math.rad(20)) and r > 55 then
				ok = false -- keep the entrance path clear
			end
			for _, p in avoid do
				if (flat(p) - flat(center + offset)).Magnitude < clearance then
					ok = false
				end
			end
			if ok then
				local spot = center + offset
				table.insert(avoid, spot)
				return spot
			end
		end
		return nil
	end

	if biome.key == "Meadow" then
		for _ = 1, 9 do
			local p = freeSpot(25, 100, 12)
			if p then
				tree(
					decor,
					p,
					rng.range(0.9, 1.4),
					Color3.fromRGB(86, 170, 74):Lerp(Color3.fromRGB(150, 210, 90), rng.next())
				)
			end
		end
		local petals = {
			Color3.fromRGB(255, 120, 160),
			Color3.fromRGB(255, 230, 90),
			Color3.fromRGB(200, 140, 255),
			WHITE,
			Color3.fromRGB(255, 160, 80),
		}
		for _ = 1, 28 do
			local p = freeSpot(15, 104, 3)
			if p then
				local stem = cylinder(
					decor,
					"Stem",
					1.4,
					0.25,
					CFrame.new(p + Vector3.new(0, 0.7, 0)),
					Color3.fromRGB(70, 150, 60)
				)
				noCollide(stem)
				local bloom =
					ball(decor, "Flower", 0.9, CFrame.new(p + Vector3.new(0, 1.5, 0)), petals[rng.int(1, #petals)])
				noCollide(bloom)
			end
		end
		for _ = 1, 6 do
			local p = freeSpot(25, 100, 8)
			if p then
				ellipsoid(
					decor,
					"Rock",
					Vector3.new(rng.range(3, 6), rng.range(2, 3.5), rng.range(3, 6)),
					CFrame.new(p + Vector3.new(0, 0.8, 0)),
					Color3.fromRGB(150, 150, 160),
					Enum.Material.Rock
				)
			end
		end
		for _ = 1, 5 do
			local p = freeSpot(20, 100, 6)
			if p then
				local stem = cylinder(
					decor,
					"MushroomStem",
					1.6,
					0.8,
					CFrame.new(p + Vector3.new(0, 0.8, 0)),
					Color3.fromRGB(245, 235, 215)
				)
				noCollide(stem)
				local cap = ellipsoid(
					decor,
					"MushroomCap",
					Vector3.new(2.6, 1.3, 2.6),
					CFrame.new(p + Vector3.new(0, 1.8, 0)),
					Color3.fromRGB(230, 70, 70)
				)
				noCollide(cap)
			end
		end
	elseif biome.key == "Candy" then
		for _ = 1, 8 do
			local p = freeSpot(25, 100, 10)
			if p then
				for i = 0, 7 do
					cylinder(
						decor,
						"CandyCane",
						1.2,
						1.4,
						CFrame.new(p + Vector3.new(0, 0.6 + i * 1.2, 0)),
						if i % 2 == 0 then Color3.fromRGB(235, 50, 70) else WHITE
					)
				end
				ball(decor, "CandyCaneTop", 1.6, CFrame.new(p + Vector3.new(0, 10, 0)), Color3.fromRGB(235, 50, 70))
			end
		end
		local swirls = {
			Color3.fromRGB(255, 120, 200),
			Color3.fromRGB(120, 220, 255),
			Color3.fromRGB(255, 230, 100),
			Color3.fromRGB(170, 255, 150),
		}
		for _ = 1, 8 do
			local p = freeSpot(25, 100, 10)
			if p then
				cylinder(decor, "LollipopStick", 7, 0.5, CFrame.new(p + Vector3.new(0, 3.5, 0)), WHITE)
				local face = CFrame.new(p + Vector3.new(0, 8.5, 0))
					* CFrame.Angles(0, rng.range(0, math.pi), 0)
					* CFrame.Angles(math.rad(90), 0, 0)
				cylinder(decor, "Lollipop", 0.6, 5, face, swirls[rng.int(1, #swirls)])
				cylinder(decor, "LollipopSwirl", 0.7, 2.8, face, WHITE)
			end
		end
		for _ = 1, 14 do
			local p = freeSpot(18, 104, 5)
			if p then
				local gum = ellipsoid(
					decor,
					"Gumdrop",
					Vector3.new(3, 3.2, 3),
					CFrame.new(p + Vector3.new(0, 0.6, 0)),
					swirls[rng.int(1, #swirls)],
					Enum.Material.Glass
				)
				gum.Transparency = 0.1
			end
		end
		for _ = 1, 4 do
			local p = freeSpot(30, 95, 14)
			if p then
				local puddle = cylinder(
					decor,
					"Chocolate",
					0.3,
					rng.range(8, 13),
					CFrame.new(p + Vector3.new(0, 0.1, 0)),
					Color3.fromRGB(110, 64, 40)
				)
				noCollide(puddle)
			end
		end
	elseif biome.key == "Clockwork" then
		local brass = Color3.fromRGB(214, 168, 84)
		local iron = Color3.fromRGB(88, 90, 102)
		local copper = Color3.fromRGB(196, 112, 72)
		-- Standing gears
		for _ = 1, 7 do
			local p = freeSpot(25, 98, 12)
			if p then
				local radius = rng.range(3.5, 6)
				local yaw = rng.range(0, math.pi)
				local hub = CFrame.new(p + Vector3.new(0, radius + 0.8, 0)) * CFrame.Angles(0, yaw, 0)
				local color = if rng.next() < 0.5 then brass else copper
				cylinder(
					decor,
					"Gear",
					1.2,
					radius * 2,
					hub * CFrame.Angles(math.rad(90), 0, 0),
					color,
					Enum.Material.Metal
				)
				for i = 1, 10 do
					local a = i / 10 * math.pi * 2
					block(
						decor,
						"Tooth",
						Vector3.new(1.2, 1.4, 1.2),
						hub * CFrame.Angles(0, 0, a) * CFrame.new(0, radius + 0.5, 0),
						color,
						Enum.Material.Metal
					)
				end
				cylinder(decor, "Axle", 1.8, 1.6, hub * CFrame.Angles(math.rad(90), 0, 0), iron, Enum.Material.Metal)
				block(
					decor,
					"Stand",
					Vector3.new(1.2, radius + 0.8, 1.2),
					CFrame.new(p + Vector3.new(0, (radius + 0.8) / 2, 0))
						* CFrame.Angles(0, yaw, 0)
						* CFrame.new(0, 0, 1.3),
					iron,
					Enum.Material.Metal
				)
			end
		end
		-- Steam pipes
		for _ = 1, 5 do
			local p = freeSpot(30, 95, 14)
			if p then
				local length = rng.range(10, 18)
				local base = CFrame.new(p + Vector3.new(0, 1.4, 0)) * CFrame.Angles(0, rng.range(0, math.pi), 0)
				cylinder(
					decor,
					"Pipe",
					length,
					1.8,
					base * CFrame.Angles(0, 0, math.rad(90)),
					copper,
					Enum.Material.Metal
				)
				for _, side in { -1, 1 } do
					cylinder(
						decor,
						"Joint",
						0.8,
						2.4,
						base * CFrame.new(side * length / 2, 0, 0) * CFrame.Angles(0, 0, math.rad(90)),
						brass,
						Enum.Material.Metal
					)
				end
				local vent = cylinder(decor, "Vent", 3, 1.4, base * CFrame.new(0, 1.5, 0), iron, Enum.Material.Metal)
				local steam = Instance.new("ParticleEmitter")
				steam.Name = "Steam"
				steam.Color = ColorSequence.new(Color3.fromRGB(235, 235, 240))
				steam.Transparency = NumberSequence.new(0.4, 1)
				steam.Size = NumberSequence.new(0.8, 3)
				steam.Rate = 4
				steam.Lifetime = NumberRange.new(1.5, 2.5)
				steam.Speed = NumberRange.new(3, 5)
				steam.SpreadAngle = Vector2.new(12, 12)
				steam.Parent = vent
			end
		end
		-- Crates and lamps
		for _ = 1, 6 do
			local p = freeSpot(20, 100, 6)
			if p then
				local size = rng.range(2.5, 4)
				block(
					decor,
					"Crate",
					Vector3.new(size, size, size),
					CFrame.new(p + Vector3.new(0, size / 2, 0)) * CFrame.Angles(0, rng.range(0, 3), 0),
					Color3.fromRGB(150, 110, 70),
					Enum.Material.WoodPlanks
				)
			end
		end
		for _ = 1, 4 do
			local p = freeSpot(25, 95, 10)
			if p then
				lamp(decor, p, Color3.fromRGB(255, 200, 120))
			end
		end
		-- Clock tower
		local towerSpot = freeSpot(40, 80, 16)
		if towerSpot then
			block(
				decor,
				"ClockTower",
				Vector3.new(7, 22, 7),
				CFrame.new(towerSpot + Vector3.new(0, 11, 0)),
				Color3.fromRGB(150, 120, 90),
				Enum.Material.Brick
			)
			block(
				decor,
				"TowerCap",
				Vector3.new(8.5, 1.5, 8.5),
				CFrame.new(towerSpot + Vector3.new(0, 22.75, 0)),
				brass,
				Enum.Material.Metal
			)
			for i = 0, 3 do
				local face = CFrame.new(towerSpot + Vector3.new(0, 17, 0))
					* CFrame.Angles(0, i * math.pi / 2, 0)
					* CFrame.new(0, 0, -3.6)
				cylinder(
					decor,
					"ClockFace",
					0.3,
					5,
					face * CFrame.Angles(math.rad(90), 0, 0),
					Color3.fromRGB(250, 244, 226)
				)
				block(decor, "Hand", Vector3.new(0.3, 2, 0.2), face * CFrame.new(0, 0.8, -0.25), iron)
				block(decor, "Hand", Vector3.new(1.6, 0.3, 0.2), face * CFrame.new(0.6, 0, -0.25), iron)
			end
		end
	elseif biome.key == "Moonlit" then
		local glowColors =
			{ Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 130, 220), Color3.fromRGB(180, 140, 255) }
		for _ = 1, 8 do
			local p = freeSpot(25, 100, 12)
			if p then
				tree(
					decor,
					p,
					rng.range(1, 1.4),
					Color3.fromRGB(110, 80, 170):Lerp(Color3.fromRGB(70, 60, 140), rng.next())
				)
			end
		end
		-- Glowing mushrooms
		for _ = 1, 12 do
			local p = freeSpot(18, 102, 6)
			if p then
				local h = rng.range(1.5, 3.5)
				local stem = cylinder(
					decor,
					"MushroomStem",
					h,
					0.8,
					CFrame.new(p + Vector3.new(0, h / 2, 0)),
					Color3.fromRGB(230, 226, 250)
				)
				noCollide(stem)
				local color = glowColors[rng.int(1, #glowColors)]
				local cap = ellipsoid(
					decor,
					"MushroomCap",
					Vector3.new(h * 1.2, h * 0.5, h * 1.2),
					CFrame.new(p + Vector3.new(0, h, 0)),
					color,
					Enum.Material.Neon
				)
				noCollide(cap)
				if rng.next() < 0.4 then
					local light = Instance.new("PointLight")
					light.Color = color
					light.Range = 10
					light.Brightness = 1.2
					light.Parent = cap
				end
			end
		end
		-- Crystal clusters
		for _ = 1, 7 do
			local p = freeSpot(25, 100, 8)
			if p then
				for _ = 1, 3 do
					local h = rng.range(3, 7)
					local crystal = block(
						decor,
						"Crystal",
						Vector3.new(1.2, h, 1.2),
						CFrame.new(p + Vector3.new(rng.range(-1.5, 1.5), h / 2 - 0.3, rng.range(-1.5, 1.5)))
							* CFrame.Angles(rng.range(-0.35, 0.35), rng.range(0, 3), rng.range(-0.35, 0.35)),
						Color3.fromRGB(200, 170, 255),
						Enum.Material.Neon
					)
					crystal.Transparency = 0.2
				end
			end
		end
		-- Floating lanterns with fireflies
		for _ = 1, 6 do
			local p = freeSpot(20, 100, 10)
			if p then
				local lantern = ball(
					decor,
					"Lantern",
					1.6,
					CFrame.new(p + Vector3.new(0, rng.range(8, 14), 0)),
					Color3.fromRGB(255, 220, 140),
					Enum.Material.Neon
				)
				noCollide(lantern)
				local light = Instance.new("PointLight")
				light.Color = Color3.fromRGB(255, 220, 140)
				light.Range = 14
				light.Brightness = 1.4
				light.Parent = lantern
				local flies = Instance.new("ParticleEmitter")
				flies.Name = "Fireflies"
				flies.Color = ColorSequence.new(Color3.fromRGB(255, 240, 140))
				flies.LightEmission = 1
				flies.Rate = 3
				flies.Lifetime = NumberRange.new(3, 5)
				flies.Speed = NumberRange.new(0.5, 1.5)
				flies.SpreadAngle = Vector2.new(180, 180)
				flies.Size = NumberSequence.new(0.18)
				flies.Parent = lantern
			end
		end
	else -- Storm
		local crystalColors =
			{ Color3.fromRGB(110, 230, 255), Color3.fromRGB(170, 130, 255), Color3.fromRGB(120, 255, 220) }
		for _ = 1, 12 do
			local p = freeSpot(22, 102, 8)
			if p then
				local h = rng.range(5, 11)
				local crystal = block(
					decor,
					"Crystal",
					Vector3.new(1.6, h, 1.6),
					CFrame.new(p + Vector3.new(0, h / 2 - 0.5, 0))
						* CFrame.Angles(rng.range(-0.3, 0.3), rng.range(0, 3), rng.range(-0.3, 0.3)),
					crystalColors[rng.int(1, #crystalColors)],
					Enum.Material.Neon
				)
				crystal.Transparency = 0.15
			end
		end
		for _ = 1, 8 do
			local p = freeSpot(30, 100, 10)
			if p then
				local h = rng.range(10, 18)
				cylinder(
					decor,
					"Spire",
					h,
					rng.range(3, 5),
					CFrame.new(p + Vector3.new(0, h / 2, 0)),
					Color3.fromRGB(60, 62, 80),
					Enum.Material.Slate
				)
			end
		end
		for _ = 1, 5 do
			local p = freeSpot(25, 100, 10)
			if p then
				cylinder(
					decor,
					"LightningRod",
					12,
					0.6,
					CFrame.new(p + Vector3.new(0, 6, 0)),
					Color3.fromRGB(180, 186, 200),
					Enum.Material.Metal
				)
				local tip = ball(
					decor,
					"RodTip",
					1.6,
					CFrame.new(p + Vector3.new(0, 12.6, 0)),
					Color3.fromRGB(255, 230, 90),
					Enum.Material.Neon
				)
				noCollide(tip)
				local light = Instance.new("PointLight")
				light.Color = Color3.fromRGB(255, 230, 120)
				light.Range = 16
				light.Brightness = 1.5
				light.Parent = tip
			end
		end
		for _ = 1, 7 do
			local a = rng.range(0, math.pi * 2)
			local r = rng.range(20, 95)
			local p = center + Vector3.new(math.cos(a) * r, rng.range(26, 36), math.sin(a) * r)
			for j = 1, 4 do
				local puff = ball(
					decor,
					"Cloud",
					rng.range(6, 10),
					CFrame.new(p + Vector3.new(j * 3.5 - 7, rng.range(-1, 1), rng.range(-2, 2))),
					Color3.fromRGB(220, 226, 240)
				)
				puff.Transparency = 0.2
				puff.CastShadow = false
				noCollide(puff)
			end
		end
	end
end

local function buildBiome(parent: Instance, biome: Config.BiomeInfo)
	local m = newModel(parent, biome.key)
	m:SetAttribute("Biome", biome.key)
	local center = biome.center
	floatingIsland(m, center, biome.radius, biome.groundColor, biome.groundMaterial, biome.edgeColor, biome.rockColor)

	local toHub = flat(-center).Unit
	local rng = Rng.new(biome.order * 7919)
	local nests = folder(m, "Nests")
	local avoid: { Vector3 } = { center }
	for i = 1, biome.nestCount do
		local a = (i - 1) / biome.nestCount * math.pi * 2 + rng.range(-0.18, 0.18)
		local r = if i % 2 == 0 then rng.range(70, 86) else rng.range(40, 56)
		local position = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local nest = Builders.nest(nests, "Nest" .. i, CFrame.new(position), biome.nestColor)
		nest:SetAttribute("Biome", biome.key)
		nest:SetAttribute("Index", i)
		table.insert(avoid, position)
	end

	local guardian = Builders.guardian(biome.guardian, CFrame.lookAt(center, center + toHub))
	guardian:SetAttribute("Biome", biome.key)
	guardian.Parent = m

	-- Entrance arch facing the bridge.
	local gatePos = center + toHub * (biome.radius - 8)
	local gateCf = CFrame.lookAt(gatePos, gatePos + toHub)
	local gate = newModel(m, "Gate")
	local pillarColor = biome.edgeColor:Lerp(WHITE, 0.2)
	for _, side in { -1, 1 } do
		block(gate, "Pillar", Vector3.new(3, 18, 3), gateCf * CFrame.new(side * 14, 9, 0), pillarColor)
		local cap = ball(gate, "Cap", 4.2, gateCf * CFrame.new(side * 14, 18.6, 0), biome.bandColor, Enum.Material.Neon)
		noCollide(cap)
	end
	local beam = block(gate, "Beam", Vector3.new(31, 3.5, 3.5), gateCf * CFrame.new(0, 16.5, 0), pillarColor)
	local subtitle = if biome.recommendedSpeed > 0
		then `Recommended Speed: {biome.recommendedSpeed}+`
		else "No Speed needed"
	sign(
		beam,
		`{biome.icon} {string.upper(biome.name)}`,
		subtitle,
		biome.bandColor:Lerp(WHITE, 0.25),
		Vector3.new(0, 6, 0),
		30,
		320
	)

	decorate(m, biome, rng, avoid, toHub)
end

local function buildBridge(parent: Instance, name: string, from: Vector3, to: Vector3, width: number)
	local m = newModel(parent, name)
	local mid = (from + to) / 2
	local length = (to - from).Magnitude
	local cf = CFrame.lookAt(mid, to)
	local wood = Color3.fromRGB(176, 128, 86)
	-- A hair below the island tops so the overlapping ends don't z-fight.
	block(m, "Deck", Vector3.new(width, 2, length), cf * CFrame.new(0, -1.06, 0), wood, Enum.Material.WoodPlanks)
	local posts = math.max(1, math.floor(length / 16))
	for _, side in { -1, 1 } do
		local x = side * (width / 2 - 0.6)
		block(
			m,
			"Rail",
			Vector3.new(1.2, 1, length),
			cf * CFrame.new(x, 2.6, 0),
			wood:Lerp(BLACK, 0.2),
			Enum.Material.Wood
		)
		for i = 0, posts do
			block(
				m,
				"Post",
				Vector3.new(1.2, 3.2, 1.2),
				cf * CFrame.new(x, 1.6, -length / 2 + i * (length / posts)),
				wood:Lerp(BLACK, 0.3),
				Enum.Material.Wood
			)
		end
	end
end

---------------------------------------------------------------------------
-- Training track
---------------------------------------------------------------------------
local function buildTraining(map: Instance)
	local T = Config.Training
	local m = newModel(map, "Training")
	local c = T.center
	local trackColor = Color3.fromRGB(206, 92, 70)

	local base = block(
		m,
		"Base",
		Vector3.new(T.outerX + 10, 4, T.outerZ + 10),
		CFrame.new(c.X, -2, c.Z),
		Config.Hub.groundColor,
		Enum.Material.Grass
	)
	base.Name = "Base"
	block(
		m,
		"Underside",
		Vector3.new(T.outerX - 10, 14, T.outerZ - 10),
		CFrame.new(c.X, -11, c.Z),
		Config.Hub.rockColor,
		Enum.Material.Rock
	)

	local width = (T.outerZ - T.innerZ) / 2
	local sideWidth = (T.outerX - T.innerX) / 2
	-- Long straights (north/south) and short straights (east/west).
	for _, side in { -1, 1 } do
		block(
			m,
			"Track",
			Vector3.new(T.outerX, 0.4, width),
			CFrame.new(c.X, 0.2, c.Z + side * (T.innerZ / 2 + width / 2)),
			trackColor,
			Enum.Material.SmoothPlastic
		)
		block(
			m,
			"Track",
			Vector3.new(sideWidth, 0.4, T.innerZ),
			CFrame.new(c.X + side * (T.innerX / 2 + sideWidth / 2), 0.2, c.Z),
			trackColor,
			Enum.Material.SmoothPlastic
		)
		local lane = block(
			m,
			"Lane",
			Vector3.new(T.innerX, 0.05, 0.4),
			CFrame.new(c.X, 0.42, c.Z + side * (T.innerZ / 2 + width / 2)),
			WHITE
		)
		noCollide(lane)
		for _, dx in { 0 } do
			local hurdle = block(
				m,
				"Hurdle",
				Vector3.new(1, 2.4, width),
				CFrame.new(c.X + dx, 1.6, c.Z + side * (T.innerZ / 2 + width / 2)),
				if dx == 0 then Color3.fromRGB(255, 220, 80) else WHITE
			)
			hurdle.Name = "Hurdle"
		end
	end

	local infield = block(
		m,
		"Infield",
		Vector3.new(T.innerX, 10, T.innerZ),
		CFrame.new(c.X, 5, c.Z),
		Color3.fromRGB(110, 190, 90),
		Enum.Material.Grass
	)
	sign(
		infield,
		"🏃 TRAINING TRACK",
		"Run laps for Speed • faster laps = bigger bonus",
		Color3.fromRGB(255, 180, 130),
		Vector3.new(0, 12, 0),
		46,
		400
	)
	for _, dx in { -50, -25, 0, 25, 50 } do
		tree(m, Vector3.new(c.X + dx, 10, c.Z), 0.8, Color3.fromRGB(96, 176, 80))
	end

	buildBridge(
		map,
		"TrainingBridge",
		Vector3.new(Config.Hub.radius - 3, 0, 0),
		Vector3.new(c.X - T.outerX / 2 + 3, 0, 0),
		22
	)
end

---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Leaderboards (the server fills in the rows)
---------------------------------------------------------------------------
local function boardFace(board: BasePart, face: Enum.NormalId, info: Config.BoardInfo)
	local gui = Instance.new("SurfaceGui")
	gui.Name = face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	Builders.text(
		gui,
		"Title",
		info.title,
		UDim2.fromScale(0.94, 0.12),
		UDim2.fromScale(0.03, 0.02),
		Color3.fromRGB(255, 214, 90),
		Enum.Font.FredokaOne
	)
	for i = 1, 10 do
		local color = if i <= 3 then Color3.fromRGB(255, 236, 170) else WHITE
		local row = Builders.text(
			gui,
			"Row" .. i,
			`{i}. ---`,
			UDim2.fromScale(0.9, 0.068),
			UDim2.fromScale(0.05, 0.15 + (i - 1) * 0.074),
			color,
			Enum.Font.GothamBold
		)
		row.TextXAlignment = Enum.TextXAlignment.Left
	end
	Builders.text(
		gui,
		"Status",
		"Leaderboards appear once the game is published",
		UDim2.fromScale(0.9, 0.05),
		UDim2.fromScale(0.05, 0.92),
		Color3.fromRGB(178, 186, 216),
		Enum.Font.GothamBold
	)
end

local function buildLeaderboards(hub: Instance)
	local boards = folder(hub, "Leaderboards")
	local list = Config.Leaderboards.boards
	for i, info in list do
		local base = CFrame.new((i - (#list + 1) / 2) * 30, 0.3, -72)
		local m = newModel(boards, info.key)
		m:SetAttribute("Stat", info.key)
		block(
			m,
			"Base",
			Vector3.new(17, 1.2, 4),
			base * CFrame.new(0, 0.6, 0),
			Color3.fromRGB(236, 232, 224),
			Enum.Material.Marble
		)
		for _, side in { -1, 1 } do
			block(
				m,
				"Post",
				Vector3.new(1.2, 21, 1.2),
				base * CFrame.new(side * 7.6, 11.7, 0),
				Color3.fromRGB(120, 84, 58),
				Enum.Material.Wood
			)
		end
		local board =
			block(m, "Board", Vector3.new(14.4, 18, 0.8), base * CFrame.new(0, 12.6, 0), Color3.fromRGB(34, 38, 66))
		block(m, "Crown", Vector3.new(16.4, 1.4, 1.6), base * CFrame.new(0, 22.3, 0), Color3.fromRGB(255, 200, 70))
		boardFace(board, Enum.NormalId.Front, info)
		boardFace(board, Enum.NormalId.Back, info)
	end
end

function MapBuilder.build(): Model
	local map = Instance.new("Model")
	map.Name = "Map"

	buildHub(map)
	buildLeaderboards(map:FindFirstChild("Hub") :: Instance)

	local plots = folder(map, "Plots")
	for i = 1, Config.Plots.count do
		buildPlot(plots, i)
	end

	local biomes = folder(map, "Biomes")
	local bridges = folder(map, "Bridges")
	for _, biome in Config.Biomes do
		buildBiome(biomes, biome)
		local from = Config.polar(biome.angle, Config.Hub.radius - 3)
		local to = Config.polar(biome.angle, biome.distance - biome.radius + 3)
		buildBridge(bridges, biome.key .. "Bridge", from, to, 22)
	end

	buildTraining(map)
	return map
end

return MapBuilder
