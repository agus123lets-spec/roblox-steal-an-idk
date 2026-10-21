--!strict
-- Shop (upgrades, tools, feather shop) and Pets (sell, slots) windows.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PetLogic = require(ReplicatedStorage.Shared.PetLogic)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UIKit = require(script.Parent.UIKit)
local ClientState = require(script.Parent.ClientState)
local HUD = require(script.Parent.HUD)
local Sounds = require(script.Parent.Sounds)

local C = UIKit.Colors

local Panels = {}

local gui: ScreenGui
local window: Frame
local titleLabel: TextLabel
local tabsBar: Frame
local content: ScrollingFrame
local current: string? = nil
local shopTab = "Upgrades"
local pendingSell: { [string]: number } = {}
local busy = false

local function clearContent()
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local rowOrder = 0
local function row(
	title: string,
	subtitle: string,
	titleColor: Color3?,
	buttonText: string?,
	buttonColor: Color3?,
	onClick: (() -> ())?
): Frame
	rowOrder += 1
	local frame = UIKit.frame(content, "Row", UDim2.new(1, -8, 0, 64), UDim2.new(), C.row, 0)
	frame.LayoutOrder = rowOrder
	UIKit.corner(frame)
	UIKit.stroke(frame, C.stroke, 2)
	local titleText =
		UIKit.label(frame, "Title", title, UDim2.new(1, -170, 0, 28), UDim2.fromOffset(12, 6), titleColor or C.text)
	titleText.TextXAlignment = Enum.TextXAlignment.Left
	UIKit.textStroke(titleText, 1.5)
	local sub = UIKit.label(
		frame,
		"Subtitle",
		subtitle,
		UDim2.new(1, -170, 0, 20),
		UDim2.fromOffset(12, 36),
		C.muted,
		UIKit.BodyFont
	)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	if buttonText then
		local button = UIKit.button(
			frame,
			"Action",
			buttonText,
			UDim2.fromOffset(140, 44),
			UDim2.new(1, -150, 0, 10),
			buttonColor or C.button,
			function()
				if onClick then
					Sounds.play("click")
					onClick()
				end
			end
		)
		button.Active = onClick ~= nil
	end
	return frame
end

local function note(text: string)
	rowOrder += 1
	local label = UIKit.label(content, "Note", text, UDim2.new(1, -8, 0, 34), UDim2.new(), C.muted, UIKit.BodyFont)
	label.LayoutOrder = rowOrder
end

local function purchase(itemId: string)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, result, message = pcall(function()
			return Remotes.Purchase:InvokeServer(itemId)
		end)
		busy = false
		if ok then
			HUD.toast(tostring(message), if result then "success" else "warn")
			Sounds.play(if result then "coin" else "error")
		else
			HUD.toast("Purchase failed, try again.", "warn")
		end
	end)
end

local function sell(petId: string)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, result, message = pcall(function()
			return Remotes.SellPet:InvokeServer(petId)
		end)
		busy = false
		if ok then
			HUD.toast(tostring(message), if result then "success" else "warn")
			Sounds.play(if result then "coin" else "error")
		end
	end)
end

---------------------------------------------------------------------------
-- Shop
---------------------------------------------------------------------------
local function renderShop(state: ClientState.State)
	local now = workspace:GetServerTimeNow()
	if shopTab == "Upgrades" then
		local shoes = Config.Shoes[state.shoesLevel]
		local nextShoes = Config.Shoes[state.shoesLevel + 1]
		if nextShoes then
			local affordable = state.coins >= nextShoes.cost
			row(
				`👟 {shoes.name} (x{shoes.mult})`,
				`Next: {nextShoes.name} - x{nextShoes.mult} Speed from training`,
				C.speed,
				Format.money(nextShoes.cost),
				if affordable then C.button else C.buttonDisabled,
				function()
					purchase("Shoes")
				end
			)
		else
			row(`👟 {shoes.name} (x{shoes.mult})`, "Best shoes in the game!", C.speed, "MAX", C.buttonDisabled, nil)
		end
		local slotCost = PetLogic.slotCost(state.slots)
		if slotCost then
			row(
				`🐾 Pen Slots {state.slots}/{Config.Plots.maxSlots}`,
				"Room for one more earning pet",
				C.coins,
				Format.money(slotCost),
				if state.coins >= slotCost then C.button else C.buttonDisabled,
				function()
					purchase("Slot")
				end
			)
		else
			row(
				`🐾 Pen Slots {state.slots}/{Config.Plots.maxSlots}`,
				"Your pen is maxed out!",
				C.coins,
				"MAX",
				C.buttonDisabled,
				nil
			)
		end
		note("Tip: faster laps on the Training Track give up to x1.6 bonus Speed.")
	elseif shopTab == "Tools" then
		row("🕸 Net Launcher", "Knock the egg off a carrier, then grab it", C.good, "OWNED", C.buttonDisabled, nil)
		if state.tools.Slime then
			row("🟢 Slime Puddle", "Slows egg carriers that run through it", C.good, "OWNED", C.buttonDisabled, nil)
		else
			local cost = Config.Tools.Slime.cost
			row(
				"🟢 Slime Puddle",
				"Slows egg carriers that run through it",
				C.good,
				Format.money(cost),
				if state.coins >= cost then C.button else C.buttonDisabled,
				function()
					purchase("Tool:Slime")
				end
			)
		end
		note("Tools only work on players carrying an egg. Nobody gets bullied for walking around.")
	else
		note(`You have {state.feathers} 🪶. Earn them when your eggs get stolen, from underdog heists and revenge.`)
		for _, item in Config.FeatherShop do
			local untilTime = if item.id == "Boost:Luck" then state.luckUntil else state.turboUntil
			local active = if untilTime > now then ` • active {Format.clock(untilTime - now)}` else ""
			row(
				`✨ {item.name}`,
				item.desc .. active,
				C.feathers,
				`{item.cost} 🪶`,
				if state.feathers >= item.cost then C.button else C.buttonDisabled,
				function()
					purchase(item.id)
				end
			)
		end
		for _, trail in Config.Trails do
			local owned = state.trails[trail.key] == true
			local equipped = state.equippedTrail == trail.key
			local buttonText = if equipped then "UNEQUIP" elseif owned then "EQUIP" else `{trail.cost} 🪶`
			local color = if owned or state.feathers >= trail.cost then C.button else C.buttonDisabled
			row(
				`🌈 {trail.name}`,
				if equipped then "Equipped" else "A glowing trail behind you",
				trail.c1,
				buttonText,
				color,
				function()
					purchase("Trail:" .. trail.key)
				end
			)
		end
	end
end

---------------------------------------------------------------------------
-- Pets
---------------------------------------------------------------------------
local function renderPets(state: ClientState.State)
	local slotCost = PetLogic.slotCost(state.slots)
	row(
		`🐾 {#state.pets}/{state.slots} pets • {Format.money(state.income)}/s`,
		if slotCost then "Buy another slot to earn more" else "Pen maxed out",
		C.coins,
		if slotCost then `+1 slot {Format.money(slotCost)}` else "MAX",
		if slotCost and state.coins >= slotCost then C.button else C.buttonDisabled,
		if slotCost
			then function()
				purchase("Slot")
			end
			else nil
	)
	if #state.pets == 0 then
		note("No pets yet! Grab an egg in 🌼 Meadow Hollow and bring it home.")
		return
	end
	local pets = table.clone(state.pets)
	table.sort(pets, function(a, b)
		return PetLogic.income(a) > PetLogic.income(b)
	end)
	local now = os.clock()
	for _, pet in pets do
		local info = Config.PetByKey[pet.kind]
		if info then
			local rarity = Config.Rarities[info.rarity]
			local biome = Config.BiomeByKey[info.biome]
			local confirming = (pendingSell[pet.id] or 0) > now
			local value = PetLogic.sellValue(pet)
			row(
				PetLogic.describe(pet),
				`{info.rarity} • {if biome then biome.name else ""} • {Format.money(PetLogic.income(pet))}/s`,
				rarity.color,
				if confirming then "Sure? Sell!" else `Sell {Format.money(value)}`,
				if confirming then C.danger else C.warn,
				function()
					if (pendingSell[pet.id] or 0) > os.clock() then
						pendingSell[pet.id] = nil
						sell(pet.id)
					else
						pendingSell[pet.id] = os.clock() + 3
						Panels.refresh()
						task.delay(3.1, Panels.refresh)
					end
				end
			)
		end
	end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local tabButtons: { [string]: TextButton } = {}

function Panels.refresh()
	if not current then
		return
	end
	clearContent()
	rowOrder = 0
	local state = ClientState.get()
	tabsBar.Visible = current == "Shop"
	content.Position = UDim2.fromOffset(16, if current == "Shop" then 112 else 66)
	content.Size = UDim2.new(1, -32, 1, if current == "Shop" then -128 else -82)
	for name, button in tabButtons do
		button.BackgroundColor3 = if name == shopTab then C.info else C.panelLight
	end
	if current == "Shop" then
		titleLabel.Text = "🛒 Shop"
		renderShop(state)
	else
		titleLabel.Text = "🐾 Your Pets"
		renderPets(state)
	end
end

local function open(name: string)
	current = name
	window.Visible = true
	Panels.refresh()
	UIKit.pop(titleLabel, 0.15)
end

local function close()
	current = nil
	window.Visible = false
end

function Panels.toggle(name: string)
	if current == name then
		close()
	else
		open(name)
	end
end

function Panels.start()
	gui = HUD.makeScreen("NestHeistPanels", 5)

	window = UIKit.frame(gui, "Window", UDim2.fromOffset(620, 470), UDim2.fromScale(0.5, 0.52), C.panel, 0.02)
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Visible = false
	UIKit.corner(window, UDim.new(0, 18))
	UIKit.stroke(window, C.stroke, 4)
	HUD.responsive(window)

	titleLabel = UIKit.label(window, "Title", "Shop", UDim2.new(1, -120, 0, 40), UDim2.fromOffset(20, 12), C.text)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	UIKit.textStroke(titleLabel, 2.5)
	UIKit.button(window, "Close", "X", UDim2.fromOffset(44, 44), UDim2.new(1, -58, 0, 12), C.danger, function()
		Sounds.play("click")
		close()
	end)

	tabsBar = UIKit.frame(window, "Tabs", UDim2.new(1, -32, 0, 40), UDim2.fromOffset(16, 62), C.panel, 1)
	UIKit.list(tabsBar, Enum.FillDirection.Horizontal, 8)
	for i, name in { "Upgrades", "Tools", "Feathers" } do
		local button = UIKit.button(
			tabsBar,
			name,
			name,
			UDim2.fromOffset(160, 38),
			UDim2.new(),
			C.panelLight,
			function()
				Sounds.play("click")
				shopTab = name
				Panels.refresh()
			end
		)
		button.LayoutOrder = i
		tabButtons[name] = button
	end

	content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 8
	content.ScrollBarImageColor3 = C.muted
	content.CanvasSize = UDim2.new()
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.Parent = window
	local layout = UIKit.list(content, Enum.FillDirection.Vertical, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	HUD.addMenuButton("🛒", "Shop", C.info, 1, function()
		Sounds.play("click")
		Panels.toggle("Shop")
	end)
	HUD.addMenuButton("🐾", "Pets", C.good, 2, function()
		Sounds.play("click")
		Panels.toggle("Pets")
	end)

	-- Coins change every second, so throttle rebuilding the open window.
	local lastRefresh = 0
	ClientState.onChanged(function()
		if current and os.clock() - lastRefresh > 0.5 then
			lastRefresh = os.clock()
			Panels.refresh()
		end
	end)
end

return Panels
