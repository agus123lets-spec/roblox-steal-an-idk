--!strict
-- Pet Index: every pet per biome as a 3D card (silhouettes until found) and completion bonuses.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PetLogic = require(ReplicatedStorage.Shared.PetLogic)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Builders = require(ReplicatedStorage.Shared.Builders)
local UIKit = require(script.Parent.Parent.UIKit)
local Types = require(script.Parent.Types)

local C = UIKit.Colors

local TABS = {}
for _, biome in Config.Biomes do
	table.insert(TABS, biome.key)
end

local function card(parent: Instance, pet: Config.PetInfo, found: boolean, order: number)
	local rarity = Config.Rarities[pet.rarity]
	local frame = UIKit.frame(parent, "Card", UDim2.fromOffset(108, 164), UDim2.new(), C.row)
	frame.LayoutOrder = order
	UIKit.corner(frame)
	UIKit.stroke(frame, if found then rarity.color else C.stroke, 2.5)

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.Size = UDim2.new(1, -12, 0, 92)
	viewport.Position = UDim2.fromOffset(6, 6)
	viewport.BackgroundColor3 = rarity.color:Lerp(Color3.new(0, 0, 0), 0.6)
	viewport.BackgroundTransparency = 0.2
	viewport.Ambient = Color3.fromRGB(170, 170, 185)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.LightDirection = Vector3.new(-0.4, -1, 0.6)
	if not found then
		viewport.ImageColor3 = Color3.new(0, 0, 0) -- silhouette until discovered
	end
	viewport.Parent = frame
	UIKit.corner(viewport)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	Builders.pet(pet.key, 1, nil, CFrame.Angles(0, math.rad(25), 0)).Parent = viewport
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 2.6, -11.7), Vector3.new(0, 1.5, 0))

	local name = UIKit.label(
		frame,
		"Name",
		if found then pet.name else "???",
		UDim2.new(1, -8, 0, 22),
		UDim2.fromOffset(4, 100),
		C.text
	)
	UIKit.textStroke(name, 1.5)
	UIKit.label(
		frame,
		"Rarity",
		pet.rarity,
		UDim2.new(1, -8, 0, 18),
		UDim2.fromOffset(4, 122),
		rarity.color,
		UIKit.BodyFont
	)
	UIKit.label(
		frame,
		"Income",
		if found then `{Format.money(pet.income)}/s` else "Not found yet",
		UDim2.new(1, -8, 0, 16),
		UDim2.fromOffset(4, 142),
		C.muted,
		UIKit.BodyFont
	)
end

local Page: Types.Page = {
	title = "📖 Pet Index",
	tabs = TABS,
	signature = function(state, tab)
		local found = {}
		for _, pet in Config.Pets do
			if pet.biome == tab and state.index[pet.key] then
				table.insert(found, pet.key)
			end
		end
		return `{table.concat(found, ",")}|{Progression.completedBiomes(state.index)}`
	end,
	render = function(ui, state, tab)
		local biome = Config.BiomeByKey[tab] or Config.Biomes[1]
		local completed = Progression.completedBiomes(state.index)
		local bonus = math.floor(Config.Index.biomeBonus * 100 + 0.5)
		ui.row(
			`📖 {Progression.discovered(state.index)}/{#Config.Pets} pets discovered`,
			`{completed}/{#Config.Biomes} biomes complete • +{completed * bonus}% income`,
			C.coins
		)
		if Progression.biomeComplete(state.index, biome.key) then
			ui.note(`✅ {biome.icon} {biome.name} complete! +{bonus}% income forever.`)
		else
			ui.note(`Discover all 5 {biome.icon} {biome.name} pets for +{bonus}% income forever. Fusing counts!`)
		end
		local grid = UIKit.frame(ui.content, "Grid", UDim2.new(1, -8, 0, 168), UDim2.new(), C.panel, 1)
		grid.LayoutOrder = ui.order()
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.fromOffset(108, 164)
		layout.CellPadding = UDim2.fromOffset(8, 8)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = grid
		for order, rarityKey in Config.RarityOrder do
			local pet = PetLogic.petFor(biome.key, rarityKey)
			if pet then
				card(grid, pet, state.index[pet.key] == true, order)
			end
		end
	end,
}

return Page
