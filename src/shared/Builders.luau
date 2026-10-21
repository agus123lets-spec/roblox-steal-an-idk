--!strict
-- Procedural visuals built only from basic parts, so the game needs no uploaded assets.
-- Every model faces -Z. Used by the map builder (also under Lune), the server and the client.

local Config = require(script.Parent.Config)
local Rng = require(script.Parent.Rng)

local Builders = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local EYE_COLOR = Color3.fromRGB(28, 26, 38)

---------------------------------------------------------------------------
-- Primitive helpers
---------------------------------------------------------------------------
local function applyBase(part: BasePart, name: string, color: Color3, material: Enum.Material?)
	part.Name = name
	part.Anchored = true
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

function Builders.noCollide(part: BasePart)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
end

function Builders.block(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	applyBase(part, name, color, material)
	part.Size = size
	part.CFrame = cf
	part.Parent = parent
	return part
end

function Builders.ball(
	parent: Instance,
	name: string,
	diameter: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	applyBase(part, name, color, material)
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.CFrame = cf
	part.Parent = parent
	return part
end

-- Block rendered as an ellipsoid that fills its Size.
function Builders.ellipsoid(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Builders.block(parent, name, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Cylinder whose axis follows cf's UpVector (Roblox cylinders run along X).
function Builders.cylinder(
	parent: Instance,
	name: string,
	height: number,
	diameter: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	applyBase(part, name, color, material)
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, diameter, diameter)
	part.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = parent
	return part
end

function Builders.wedge(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): WedgePart
	local part = Instance.new("WedgePart")
	applyBase(part, name, color, material)
	part.Size = size
	part.CFrame = cf
	part.Parent = parent
	return part
end

function Builders.billboard(parent: Instance, offset: Vector3, size: UDim2, maxDistance: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Parent = parent
	return gui
end

function Builders.text(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	position: UDim2,
	color: Color3,
	font: Enum.Font
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.FontFace = Font.fromEnum(font)
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromRGB(20, 18, 34)
	label.Parent = parent
	return label
end

local function sparkles(parent: BasePart, color: Color3, rate: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkles"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = parent
end

local function glow(parent: BasePart, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Parent = parent
end

---------------------------------------------------------------------------
-- Eggs
---------------------------------------------------------------------------
function Builders.egg(rarity: string, biomeKey: string, jackpot: boolean): Model
	local rarityInfo = Config.Rarities[rarity] or Config.Rarities.Common
	local biome = Config.BiomeByKey[biomeKey]
	local scale = if jackpot then 1.35 else 1
	local model = Instance.new("Model")
	model.Name = rarity .. "Egg"

	local material = Enum.Material.SmoothPlastic
	if jackpot or rarityInfo.order >= 5 then
		material = Enum.Material.Neon
	elseif rarityInfo.order >= 3 then
		material = Enum.Material.Glass
	end

	local size = Vector3.new(2.4, 3, 2.4) * scale
	local shell = Builders.ellipsoid(model, "Shell", size, CFrame.new(), rarityInfo.color, material)
	shell.Reflectance = if rarityInfo.order >= 3 then 0.12 else 0
	shell.Massless = true
	Builders.noCollide(shell)

	local band = Builders.cylinder(
		model,
		"Band",
		0.42 * scale,
		size.X + 0.14,
		CFrame.new(0, -0.2 * scale, 0),
		if biome then biome.bandColor else WHITE
	)
	band.Anchored = false
	band.Massless = true
	Builders.noCollide(band)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = shell
	weld.Part1 = band
	weld.Parent = shell

	if jackpot or rarityInfo.order >= 3 then
		glow(shell, rarityInfo.color, 10, if jackpot then 3 else 1.5)
	end
	if jackpot or rarityInfo.order >= 4 then
		sparkles(shell, rarityInfo.color, if jackpot then 14 else 6)
	end

	model.PrimaryPart = shell
	return model
end

---------------------------------------------------------------------------
-- Pets
---------------------------------------------------------------------------
-- Builds a pet standing on `base` (feet at base's origin). `scale` comes from the pet's size.
function Builders.pet(kind: string, scale: number, mutation: string?, base: CFrame): Model
	local info = Config.PetByKey[kind] or Config.Pets[1]
	local model = Instance.new("Model")
	model.Name = info.name

	local root = Builders.block(model, "Root", Vector3.new(0.4, 0.4, 0.4), base, WHITE)
	root.Transparency = 1
	Builders.noCollide(root)
	model.PrimaryPart = root

	local body = info.body
	local accent = info.accent
	local dark = body:Lerp(BLACK, 0.25)
	local bodyParts: { BasePart } = {}
	local accentParts: { BasePart } = {}

	local function at(x: number, y: number, z: number, rotation: CFrame?): CFrame
		local cf = base * CFrame.new(x * scale, y * scale, z * scale)
		return if rotation then cf * rotation else cf
	end
	local function E(
		name: string,
		size: Vector3,
		x: number,
		y: number,
		z: number,
		color: Color3,
		rotation: CFrame?
	): Part
		local part = Builders.ellipsoid(model, name, size * scale, at(x, y, z, rotation), color)
		Builders.noCollide(part)
		if color == body or color == dark then
			table.insert(bodyParts, part)
		elseif color == accent then
			table.insert(accentParts, part)
		end
		return part
	end
	local function B(name: string, diameter: number, x: number, y: number, z: number, color: Color3): Part
		local part = Builders.ball(model, name, diameter * scale, at(x, y, z), color)
		Builders.noCollide(part)
		if color == body then
			table.insert(bodyParts, part)
		elseif color == accent then
			table.insert(accentParts, part)
		end
		return part
	end
	local function eyes(x: number, y: number, z: number, d: number)
		for _, side in { -1, 1 } do
			B("Eye", d, side * x, y, z, EYE_COLOR)
			B("Shine", d * 0.38, side * (x + d * 0.12), y + d * 0.18, z - d * 0.32, WHITE)
		end
	end
	local blush = Color3.fromRGB(255, 150, 170)

	if info.shape == "blob" then
		E("Body", Vector3.new(2.6, 2.2, 2.6), 0, 1.1, 0, body)
		E("Belly", Vector3.new(1.7, 1.3, 0.6), 0, 0.9, -1.05, accent)
		eyes(0.5, 1.55, -1.08, 0.42)
		E("Mouth", Vector3.new(0.5, 0.16, 0.12), 0, 1.18, -1.27, EYE_COLOR)
		for _, side in { -1, 1 } do
			E("Cheek", Vector3.new(0.36, 0.22, 0.1), side * 0.86, 1.3, -1.08, blush)
		end
		B("Sprout", 0.55, 0, 2.32, 0, accent)
	elseif info.shape == "bunny" then
		E("Body", Vector3.new(1.9, 1.8, 2.0), 0, 0.95, 0, body)
		B("Head", 1.65, 0, 2.15, -0.55, body)
		for _, side in { -1, 1 } do
			local tilt = CFrame.Angles(0, 0, side * -0.15)
			E("Ear", Vector3.new(0.42, 1.45, 0.26), side * 0.38, 3.35, -0.5, body, tilt)
			E("InnerEar", Vector3.new(0.22, 1.0, 0.1), side * 0.38, 3.32, -0.64, accent, tilt)
			E("Foot", Vector3.new(0.6, 0.35, 0.9), side * 0.5, 0.18, -0.45, dark)
		end
		eyes(0.38, 2.3, -1.28, 0.34)
		B("Nose", 0.18, 0, 2.05, -1.38, blush)
		B("Tail", 0.6, 0, 1.0, 1.0, accent)
	elseif info.shape == "bird" then
		E("Body", Vector3.new(1.9, 2.0, 2.0), 0, 1.1, 0, body)
		B("Head", 1.45, 0, 2.35, -0.45, body)
		E("Beak", Vector3.new(0.45, 0.32, 0.7), 0, 2.2, -1.25, Color3.fromRGB(255, 170, 60))
		eyes(0.36, 2.5, -1.08, 0.32)
		for _, side in { -1, 1 } do
			E("Wing", Vector3.new(0.32, 1.25, 1.55), side * 1.0, 1.25, 0.1, accent, CFrame.Angles(0, 0, side * 0.25))
			E("Foot", Vector3.new(0.35, 0.2, 0.55), side * 0.4, 0.1, -0.2, Color3.fromRGB(255, 170, 60))
		end
		E("Crest", Vector3.new(0.25, 0.7, 0.5), 0, 3.1, -0.4, accent)
		E("TailFeathers", Vector3.new(0.9, 0.25, 0.9), 0, 1.0, 1.1, accent, CFrame.Angles(math.rad(-25), 0, 0))
	elseif info.shape == "dragon" then
		E("Body", Vector3.new(2.2, 2.0, 2.8), 0, 1.2, 0, body)
		E("Head", Vector3.new(1.7, 1.5, 1.9), 0, 2.5, -1.45, body)
		E("Snout", Vector3.new(1.1, 0.8, 0.9), 0, 2.25, -2.3, body)
		eyes(0.45, 2.75, -2.17, 0.34)
		for _, side in { -1, 1 } do
			B("Nostril", 0.14, side * 0.22, 2.4, -2.74, EYE_COLOR)
			E(
				"Horn",
				Vector3.new(0.28, 0.85, 0.28),
				side * 0.42,
				3.35,
				-1.2,
				accent,
				CFrame.Angles(math.rad(25), 0, side * -0.2)
			)
			local wing = Builders.wedge(
				model,
				"Wing",
				Vector3.new(0.15, 1.8, 2.0) * scale,
				at(side * 1.35, 2.5, 0.2, CFrame.Angles(0, 0, side * -0.6)),
				accent
			)
			Builders.noCollide(wing)
			table.insert(accentParts, wing)
			for _, front in { -1, 1 } do
				E("Leg", Vector3.new(0.6, 0.75, 0.6), side * 0.75, 0.38, front * 0.9, dark)
			end
		end
		E("Tail", Vector3.new(0.7, 0.6, 2.2), 0, 1.0, 2.2, body, CFrame.Angles(math.rad(15), 0, 0))
		B("TailTip", 0.6, 0, 0.75, 3.25, accent)
		for i = 0, 2 do
			B("Spike", 0.45, 0, 2.25 - i * 0.1, 0.9 - i * 0.6, accent)
		end
	else -- critter: cat, fox, wolf, bear, mouse, lion
		local variant = info.variant
		E("Body", Vector3.new(2.0, 1.7, 2.4), 0, 1.15, 0, body)
		if variant == "lion" then
			E("Mane", Vector3.new(2.7, 2.6, 1.1), 0, 2.4, -0.55, accent)
		end
		E("Head", Vector3.new(1.9, 1.75, 1.75), 0, 2.35, -0.95, body)
		E("Snout", Vector3.new(0.9, 0.6, 0.55), 0, 2.05, -1.8, if variant == "mouse" then body else accent)
		B("Nose", 0.24, 0, 2.25, -2.06, EYE_COLOR)
		eyes(0.42, 2.55, -1.72, 0.36)
		for _, side in { -1, 1 } do
			if variant == "bear" or variant == "lion" then
				B("Ear", 0.7, side * 0.65, 3.05, -0.85, body)
			elseif variant == "mouse" then
				B("Ear", 1.0, side * 0.75, 3.1, -0.8, body)
				E("InnerEar", Vector3.new(0.6, 0.6, 0.1), side * 0.75, 3.1, -0.92, accent)
			else
				E("Ear", Vector3.new(0.45, 0.85, 0.28), side * 0.55, 3.0, -0.85, body, CFrame.Angles(0, 0, side * -0.3))
				E(
					"InnerEar",
					Vector3.new(0.22, 0.5, 0.1),
					side * 0.55,
					2.98,
					-1.0,
					accent,
					CFrame.Angles(0, 0, side * -0.3)
				)
			end
			for _, front in { -1, 1 } do
				E("Leg", Vector3.new(0.55, 0.7, 0.55), side * 0.6, 0.35, front * 0.75, dark)
			end
		end
		if variant == "fox" then
			E("Tail", Vector3.new(0.8, 0.8, 1.6), 0, 1.5, 1.6, body, CFrame.Angles(math.rad(-30), 0, 0))
			B("TailTip", 0.7, 0, 1.95, 2.3, WHITE)
		elseif variant == "wolf" then
			E("Tail", Vector3.new(0.6, 0.6, 1.5), 0, 1.4, 1.55, body, CFrame.Angles(math.rad(-20), 0, 0))
		elseif variant == "mouse" then
			E("Tail", Vector3.new(0.18, 0.18, 1.8), 0, 0.9, 1.9, accent, CFrame.Angles(math.rad(-10), 0, 0))
		elseif variant == "bear" then
			B("Tail", 0.45, 0, 1.2, 1.2, body)
		elseif variant == "lion" then
			E("Tail", Vector3.new(0.25, 0.25, 1.4), 0, 1.3, 1.6, body, CFrame.Angles(math.rad(-20), 0, 0))
			B("TailTuft", 0.5, 0, 1.55, 2.25, accent)
		else
			E("Tail", Vector3.new(0.3, 0.3, 1.5), 0, 1.6, 1.5, body, CFrame.Angles(math.rad(-45), 0, 0))
		end
	end

	-- Mutation looks
	local mutationInfo = nil
	for _, m in Config.Mutations do
		if m.key == mutation then
			mutationInfo = m
		end
	end
	local mainPart = bodyParts[1] or root
	if mutationInfo then
		if mutationInfo.key == "Glitter" then
			for _, part in bodyParts do
				part.Reflectance = 0.2
			end
			sparkles(mainPart, mutationInfo.color, 5)
		elseif mutationInfo.key == "Diamond" then
			for _, part in bodyParts do
				part.Material = Enum.Material.Glass
				part.Color = part.Color:Lerp(mutationInfo.color, 0.45)
				part.Reflectance = 0.3
			end
			sparkles(mainPart, WHITE, 6)
		elseif mutationInfo.key == "Starlight" then
			for _, part in bodyParts do
				part.Color = part.Color:Lerp(Color3.fromRGB(110, 60, 210), 0.35)
			end
			for _, part in accentParts do
				part.Material = Enum.Material.Neon
			end
			sparkles(mainPart, mutationInfo.color, 10)
			glow(mainPart, mutationInfo.color, 12, 2)
		end
	end

	return model
end

---------------------------------------------------------------------------
-- Guardians
---------------------------------------------------------------------------
function Builders.guardian(info: Config.GuardianInfo, base: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Guardian"
	local root = Builders.block(model, "Root", Vector3.new(1, 1, 1), base, WHITE)
	root.Transparency = 1
	Builders.noCollide(root)
	model.PrimaryPart = root

	local body = info.body
	local accent = info.accent
	local dark = body:Lerp(BLACK, 0.3)
	local light = body:Lerp(WHITE, 0.35)
	local height = 10

	local function at(x: number, y: number, z: number, rotation: CFrame?): CFrame
		local cf = base * CFrame.new(x, y, z)
		return if rotation then cf * rotation else cf
	end
	local function E(
		name: string,
		size: Vector3,
		x: number,
		y: number,
		z: number,
		color: Color3,
		rotation: CFrame?,
		material: Enum.Material?
	): Part
		local part = Builders.ellipsoid(model, name, size, at(x, y, z, rotation), color, material)
		Builders.noCollide(part)
		return part
	end
	local function B(
		name: string,
		diameter: number,
		x: number,
		y: number,
		z: number,
		color: Color3,
		material: Enum.Material?
	): Part
		local part = Builders.ball(model, name, diameter, at(x, y, z), color, material)
		Builders.noCollide(part)
		return part
	end
	local function C(
		name: string,
		length: number,
		diameter: number,
		x: number,
		y: number,
		z: number,
		color: Color3,
		rotation: CFrame?
	): Part
		local part = Builders.cylinder(model, name, length, diameter, at(x, y, z, rotation), color)
		Builders.noCollide(part)
		return part
	end

	if info.style == "Boar" then
		height = 9
		E("Body", Vector3.new(8, 6.6, 11), 0, 4.6, 0.5, body)
		E("Head", Vector3.new(5.6, 5, 5.4), 0, 5.2, -5.4, body)
		C("Snout", 1.8, 2.8, 0, 4.4, -8.2, Color3.fromRGB(236, 150, 150), CFrame.Angles(math.rad(90), 0, 0))
		for _, side in { -1, 1 } do
			B("Nostril", 0.5, side * 0.5, 4.5, -9.1, EYE_COLOR)
			E(
				"Tusk",
				Vector3.new(0.6, 2.0, 0.6),
				side * 1.25,
				3.9,
				-8.0,
				Color3.fromRGB(250, 244, 226),
				CFrame.Angles(math.rad(-25), 0, side * 0.25)
			)
			E(
				"Ear",
				Vector3.new(1.4, 2.0, 0.6),
				side * 1.9,
				7.6,
				-4.6,
				accent,
				CFrame.Angles(math.rad(-20), 0, side * -0.4)
			)
			B("Eye", 1.0, side * 1.35, 6.1, -7.6, EYE_COLOR)
			E("Brow", Vector3.new(1.6, 0.4, 0.5), side * 1.35, 6.9, -7.45, accent, CFrame.Angles(0, 0, side * 0.35))
			for _, front in { -1, 1 } do
				C("Leg", 3.2, 2.0, side * 2.6, 1.6, front * 3.6, accent)
			end
		end
		for i = 1, 5 do
			E("Bristle", Vector3.new(0.7, 1.6, 1.4), 0, 7.9, 3.5 - i * 1.6, accent, CFrame.Angles(math.rad(-25), 0, 0))
		end
		E("Tail", Vector3.new(0.5, 0.5, 2.0), 0, 6.0, 6.0, accent, CFrame.Angles(math.rad(-40), 0, 0))
	elseif info.style == "Golem" then
		height = 15
		E("Body", Vector3.new(8.5, 9, 6.5), 0, 6.2, 0, body)
		E("Belly", Vector3.new(5.5, 5.5, 1.2), 0, 5.8, -2.9, WHITE)
		E("BellySwirl", Vector3.new(3.4, 3.4, 1.3), 0, 5.8, -2.95, accent)
		E("Head", Vector3.new(5.2, 4.6, 4.6), 0, 11.6, -0.3, light)
		E("Mouth", Vector3.new(1.8, 0.4, 0.3), 0, 10.9, -2.45, EYE_COLOR)
		for _, side in { -1, 1 } do
			E("Arm", Vector3.new(2.8, 6.4, 2.8), side * 5.6, 6.6, 0, body, CFrame.Angles(0, 0, side * 0.25))
			B("Fist", 3.0, side * 6.3, 3.4, -0.2, accent)
			E("Leg", Vector3.new(3.2, 3.4, 3.2), side * 2.2, 1.7, 0, body)
			B("Eye", 0.95, side * 1.1, 12.0, -2.4, EYE_COLOR)
		end
		local rng = Rng.new(4242)
		local sprinkleColors = {
			Color3.fromRGB(255, 255, 255),
			Color3.fromRGB(120, 220, 255),
			Color3.fromRGB(255, 240, 110),
			Color3.fromRGB(150, 255, 160),
		}
		for _ = 1, 16 do
			local theta = rng.range(-math.pi, math.pi)
			local phi = rng.range(-0.9, 1.1)
			local x = 4.25 * math.cos(phi) * math.sin(theta)
			local y = 6.2 + 4.5 * math.sin(phi)
			local z = -3.25 * math.cos(phi) * math.cos(theta)
			local sprinkle = Builders.block(
				model,
				"Sprinkle",
				Vector3.new(0.3, 0.3, 0.9),
				at(x, y, z, CFrame.Angles(rng.range(0, 3), rng.range(0, 3), rng.range(0, 3))),
				sprinkleColors[rng.int(1, #sprinkleColors)]
			)
			Builders.noCollide(sprinkle)
		end
		C("Stick", 3, 0.4, 0, 14.8, -0.3, WHITE)
		C("Lollipop", 0.5, 3.2, 0, 16.9, -0.3, accent, CFrame.Angles(math.rad(90), 0, 0))
		C("LollipopSwirl", 0.55, 1.8, 0, 16.9, -0.3, Color3.fromRGB(120, 220, 255), CFrame.Angles(math.rad(90), 0, 0))
	else -- Ram
		height = 11
		E("Body", Vector3.new(7.6, 6.6, 10), 0, 5.4, 0.6, body)
		local wool = body:Lerp(WHITE, 0.45)
		local woolSpots = {
			{ -2.6, 7.6, -1.5 },
			{ 2.6, 7.6, -1.5 },
			{ 0, 8.4, 0.5 },
			{ -2.8, 7.4, 2.6 },
			{ 2.8, 7.4, 2.6 },
			{ 0, 8.0, 3.6 },
		}
		for _, spot in woolSpots do
			B("Wool", 3.6, spot[1], spot[2], spot[3], wool)
		end
		E("Head", Vector3.new(4.2, 4.6, 5.0), 0, 7.6, -5.0, dark)
		E("Muzzle", Vector3.new(3.0, 2.4, 2.0), 0, 6.6, -7.2, dark:Lerp(BLACK, 0.2))
		for _, side in { -1, 1 } do
			B("Horn", 2.6, side * 2.7, 9.0, -4.6, accent)
			B("Horn", 2.2, side * 3.5, 7.9, -3.7, accent)
			B("Horn", 1.8, side * 3.4, 6.7, -4.6, accent)
			B("Horn", 1.3, side * 2.9, 6.1, -5.6, accent)
			B("Eye", 0.9, side * 1.25, 8.3, -6.9, EYE_COLOR)
			for _, front in { -1, 1 } do
				C("Leg", 3.4, 1.8, side * 2.4, 1.7, front * 3.4, dark)
			end
		end
		for i = 0, 2 do
			local bolt = Builders.wedge(
				model,
				"Bolt",
				Vector3.new(0.5, 1.6, 1.4),
				at(0, 9.6, 2.6 - i * 1.8, CFrame.Angles(0, 0, if i % 2 == 0 then 0.5 else -0.5)),
				accent,
				Enum.Material.Neon
			)
			Builders.noCollide(bolt)
		end
		B("Tail", 1.6, 0, 6.6, 5.8, wool)
	end

	model:SetAttribute("Height", height)
	local tag = Builders.billboard(root, Vector3.new(0, height + 3, 0), UDim2.fromScale(14, 4), 220)
	tag.Name = "Tag"
	Builders.text(
		tag,
		"NameLabel",
		info.name,
		UDim2.fromScale(1, 0.6),
		UDim2.fromScale(0, 0),
		Color3.fromRGB(255, 236, 200),
		Enum.Font.FredokaOne
	)
	Builders.text(
		tag,
		"StateLabel",
		"💤",
		UDim2.fromScale(1, 0.4),
		UDim2.fromScale(0, 0.6),
		WHITE,
		Enum.Font.FredokaOne
	)
	return model
end

---------------------------------------------------------------------------
-- Nests
---------------------------------------------------------------------------
function Builders.nest(parent: Instance, name: string, base: CFrame, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = name
	Builders.cylinder(model, "Base", 1, 7, base * CFrame.new(0, 0.5, 0), color, Enum.Material.Wood)
	local hollow = Builders.cylinder(
		model,
		"Hollow",
		0.25,
		5.2,
		base * CFrame.new(0, 1.02, 0),
		color:Lerp(BLACK, 0.35),
		Enum.Material.Wood
	)
	Builders.noCollide(hollow)
	for i = 1, 10 do
		local angle = (i / 10) * math.pi * 2
		local tilt = math.rad((i * 37) % 30 - 15)
		local twig = Builders.block(
			model,
			"Twig",
			Vector3.new(0.45, 0.45, 2.6),
			base * CFrame.Angles(0, angle, 0) * CFrame.new(3.25, 1.05, 0) * CFrame.Angles(tilt, 0, 0),
			color:Lerp(WHITE, if i % 2 == 0 then 0.12 else 0),
			Enum.Material.Wood
		)
		Builders.noCollide(twig)
	end
	local spot = Builders.block(model, "Spot", Vector3.new(1, 1, 1), base * CFrame.new(0, 2.6, 0), WHITE)
	spot.Transparency = 1
	Builders.noCollide(spot)
	model.PrimaryPart = spot
	model.Parent = parent
	return model
end

return Builders
