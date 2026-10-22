--!strict
-- Heads-up display: stats, objective, toasts, banners, carry/chase alerts, revenge timer,
-- lap timer, floating "+N" popups and the dash cooldown.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")
local UserInputService: UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UIKit = require(script.Parent.UIKit)
local ClientState = require(script.Parent.ClientState)
local Sounds = require(script.Parent.Sounds)

local player = Players.LocalPlayer
local C = UIKit.Colors

local HUD = {}

local gui: ScreenGui
local responsiveScales: { UIScale } = {}

local function computeScale(): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 1
	end
	local viewport = camera.ViewportSize
	return math.clamp(math.min(viewport.X / 1150, viewport.Y / 680), 0.68, 1.1)
end

-- Keeps a UI group readable on phones and big monitors alike.
function HUD.responsive(target: GuiObject)
	local scale = Instance.new("UIScale")
	scale.Name = "Responsive"
	scale.Scale = computeScale()
	scale.Parent = target
	table.insert(responsiveScales, scale)
end

local function makeScreen(name: string, order: number): ScreenGui
	local screen = Instance.new("ScreenGui")
	screen.Name = name
	screen.ResetOnSpawn = false
	screen.DisplayOrder = order
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")
	return screen
end
HUD.makeScreen = makeScreen

local function anchored(frame: GuiObject, x: number, y: number)
	frame.AnchorPoint = Vector2.new(x, y)
end

---------------------------------------------------------------------------
-- Stats bar
---------------------------------------------------------------------------
local coinsValue: TextLabel
local coinsSub: TextLabel
local speedValue: TextLabel
local speedSub: TextLabel
local feathersValue: TextLabel
local boostsLabel: TextLabel
local displayedCoins = 0
local lastSpeed = -1
local lastFeathers = -1

local function pill(
	parent: Instance,
	name: string,
	icon: string,
	color: Color3,
	width: number,
	order: number
): (Frame, TextLabel, TextLabel)
	local frame = UIKit.frame(parent, name, UDim2.fromOffset(width, 54), UDim2.new(), C.panel, 0.08)
	frame.LayoutOrder = order
	UIKit.corner(frame, UDim.new(0.5, 0))
	UIKit.stroke(frame, C.stroke, 3)
	UIKit.label(frame, "Icon", icon, UDim2.fromOffset(40, 40), UDim2.fromOffset(8, 7))
	local value = UIKit.label(frame, "Value", "0", UDim2.new(1, -62, 0, 30), UDim2.fromOffset(52, 4), color)
	value.TextXAlignment = Enum.TextXAlignment.Left
	UIKit.textStroke(value)
	local sub =
		UIKit.label(frame, "Sub", "", UDim2.new(1, -62, 0, 16), UDim2.fromOffset(52, 33), C.muted, UIKit.BodyFont)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	return frame, value, sub
end

local function buildStats()
	local column = UIKit.frame(gui, "TopColumn", UDim2.fromOffset(640, 190), UDim2.new(0.5, 0, 0, 8), C.panel, 1)
	anchored(column, 0.5, 0)
	HUD.responsive(column)

	local bar = UIKit.frame(column, "Stats", UDim2.new(1, 0, 0, 56), UDim2.new(), C.panel, 1)
	local layout = UIKit.list(bar, Enum.FillDirection.Horizontal, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local _, cv, cs = pill(bar, "Coins", "💰", C.coins, 230, 1)
	coinsValue, coinsSub = cv, cs
	local _, sv, ss = pill(bar, "Speed", "⚡", C.speed, 200, 2)
	speedValue, speedSub = sv, ss
	local _, fv, fs = pill(bar, "Feathers", "🪶", C.feathers, 150, 3)
	feathersValue = fv
	fs.Text = "feathers"

	boostsLabel =
		UIKit.label(column, "Boosts", "", UDim2.new(1, 0, 0, 20), UDim2.fromOffset(0, 60), C.good, UIKit.BodyFont)
	UIKit.textStroke(boostsLabel, 1.5)
end

local function refreshStats(state: ClientState.State)
	coinsSub.Text = `+{Format.money(state.income)}/s`
	if state.speed ~= lastSpeed then
		if lastSpeed >= 0 and state.speed > lastSpeed then
			UIKit.pop(speedValue)
			for _, biome in Config.Biomes do
				local needed = biome.recommendedSpeed
				if needed > 0 and lastSpeed < needed and state.speed >= needed then
					HUD.announce(`🔓 {biome.icon} {biome.name} unlocked! You can outrun its guardian now.`, "success")
					Sounds.play("jackpot", 1.2)
				end
			end
		end
		lastSpeed = state.speed
		speedValue.Text = Format.short(state.speed)
	end
	speedSub.Text = `walk speed {string.format("%.1f", state.walkSpeed)}`
	if state.feathers ~= lastFeathers then
		if lastFeathers >= 0 then
			UIKit.pop(feathersValue)
		end
		lastFeathers = state.feathers
		feathersValue.Text = Format.short(state.feathers)
	end
end

---------------------------------------------------------------------------
-- Left menu
---------------------------------------------------------------------------
local menu: Frame

local function buildMenu()
	menu = UIKit.frame(gui, "Menu", UDim2.fromOffset(96, 0), UDim2.new(0, 12, 0.46, 0), C.panel, 1)
	menu.AutomaticSize = Enum.AutomaticSize.Y
	anchored(menu, 0, 0.5)
	HUD.responsive(menu)
	UIKit.list(menu, Enum.FillDirection.Vertical, 8)
end

function HUD.addMenuButton(icon: string, text: string, color: Color3, order: number, onClick: () -> ()): TextButton
	local button = UIKit.button(menu, text, `{icon}\n{text}`, UDim2.fromOffset(90, 62), UDim2.new(), color, onClick)
	button.LayoutOrder = order
	return button
end

---------------------------------------------------------------------------
-- Objective, revenge
---------------------------------------------------------------------------
local objectiveLabel: TextLabel
local revengeFrame: Frame
local revengeLabel: TextLabel
local revengeName = ""
local revengeEnds = 0

local function buildObjective()
	local column = gui:FindFirstChild("TopColumn") :: Frame
	local objective =
		UIKit.frame(column, "Objective", UDim2.fromOffset(520, 38), UDim2.new(0.5, 0, 0, 86), C.panel, 0.2)
	anchored(objective, 0.5, 0)
	UIKit.corner(objective)
	UIKit.stroke(objective, C.stroke, 2)
	objectiveLabel =
		UIKit.label(objective, "Text", "", UDim2.new(1, -24, 1, -10), UDim2.fromOffset(12, 5), C.text, UIKit.BodyFont)

	revengeFrame = UIKit.frame(column, "Revenge", UDim2.fromOffset(420, 38), UDim2.new(0.5, 0, 0, 132), C.danger, 0.1)
	anchored(revengeFrame, 0.5, 0)
	UIKit.corner(revengeFrame)
	UIKit.stroke(revengeFrame, C.stroke, 2)
	revengeLabel = UIKit.label(revengeFrame, "Text", "", UDim2.new(1, -20, 1, -8), UDim2.fromOffset(10, 4), C.text)
	UIKit.textStroke(revengeLabel)
	revengeFrame.Visible = false
end

---------------------------------------------------------------------------
-- Toasts & banners
---------------------------------------------------------------------------
local toastHolder: Frame
local bannerLabel: TextLabel
local bannerToken = 0

local function buildToasts()
	toastHolder = UIKit.frame(gui, "Toasts", UDim2.fromOffset(350, 300), UDim2.new(1, -12, 0.66, 0), C.panel, 1)
	anchored(toastHolder, 1, 1)
	HUD.responsive(toastHolder)
	local layout = UIKit.list(toastHolder, Enum.FillDirection.Vertical, 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right

	local banner = UIKit.frame(gui, "Banner", UDim2.fromOffset(720, 50), UDim2.fromScale(0.5, 0.27), C.panel, 1)
	anchored(banner, 0.5, 0.5)
	HUD.responsive(banner)
	bannerLabel = UIKit.label(banner, "Text", "", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), C.coins)
	anchored(bannerLabel, 0.5, 0.5) -- pops grow from the centre
	UIKit.textStroke(bannerLabel, 3)
	UIKit.fadeText(bannerLabel, 0, 1)
end

local toastOrder = 0
function HUD.toast(text: string, kind: string?)
	toastOrder += 1
	local color = UIKit.kindColor(kind)
	local toast = UIKit.frame(toastHolder, "Toast", UDim2.fromOffset(340, 0), UDim2.new(), C.panel, 0.05)
	toast.LayoutOrder = toastOrder
	toast.AutomaticSize = Enum.AutomaticSize.Y
	UIKit.corner(toast, UDim.new(0, 10))
	UIKit.stroke(toast, color, 2.5)
	UIKit.padding(toast, 10)
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextSize = 17
	label.FontFace = Font.fromEnum(UIKit.BodyFont)
	label.TextColor3 = C.text
	label.Text = text
	label.Parent = toast
	local accent = UIKit.frame(toast, "Accent", UDim2.new(0, 4, 1, 0), UDim2.fromOffset(-8, 0), color)
	UIKit.corner(accent, UDim.new(1, 0))
	UIKit.pop(toast, 0.08)

	local children = 0
	for _, child in toastHolder:GetChildren() do
		if child:IsA("Frame") then
			children += 1
		end
	end
	if children > 5 then
		local oldest: Frame? = nil
		for _, child in toastHolder:GetChildren() do
			if child:IsA("Frame") and (oldest == nil or child.LayoutOrder < (oldest :: Frame).LayoutOrder) then
				oldest = child
			end
		end
		if oldest then
			oldest:Destroy()
		end
	end

	task.delay(if kind == "danger" or kind == "rare" then 7 else 5, function()
		if toast.Parent then
			UIKit.tween(toast, 0.3, { BackgroundTransparency = 1 })
			UIKit.tween(label, 0.3, { TextTransparency = 1 })
			local border = toast:FindFirstChildOfClass("UIStroke")
			if border then
				UIKit.tween(border, 0.3, { Transparency = 1 })
			end
			task.wait(0.3)
			toast:Destroy()
		end
	end)
end

function HUD.announce(text: string, kind: string?)
	bannerToken += 1
	local token = bannerToken
	bannerLabel.Text = text
	bannerLabel.TextColor3 = if kind == "rare" then C.coins else UIKit.kindColor(kind)
	UIKit.fadeText(bannerLabel, 0, 0)
	UIKit.pop(bannerLabel, 0.25)
	task.delay(4.5, function()
		if token == bannerToken then
			UIKit.fadeText(bannerLabel, 0.5, 1)
		end
	end)
end

---------------------------------------------------------------------------
-- Carry banner, guardian alert, vignette
---------------------------------------------------------------------------
local carryFrame: Frame
local carryLabel: TextLabel
local carrying: { rarity: string, biome: string, jackpot: boolean }? = nil
local alertLabel: TextLabel
local vignette: { Frame } = {}
local chasedBy: string? = nil

local function buildAlerts()
	carryFrame = UIKit.frame(gui, "Carry", UDim2.fromOffset(470, 48), UDim2.new(0.5, 0, 1, -92), C.panel, 0.08)
	anchored(carryFrame, 0.5, 1)
	HUD.responsive(carryFrame)
	UIKit.corner(carryFrame)
	UIKit.stroke(carryFrame, C.coins, 3)
	carryLabel = UIKit.label(carryFrame, "Text", "", UDim2.new(1, -20, 1, -10), UDim2.fromOffset(10, 5), C.text)
	UIKit.textStroke(carryLabel)
	carryFrame.Visible = false

	local alertHolder = UIKit.frame(gui, "Alert", UDim2.fromOffset(760, 70), UDim2.fromScale(0.5, 0.36), C.panel, 1)
	anchored(alertHolder, 0.5, 0.5)
	HUD.responsive(alertHolder)
	alertLabel = UIKit.label(alertHolder, "Text", "", UDim2.fromScale(1, 1), UDim2.new(), C.danger)
	UIKit.textStroke(alertLabel, 3)
	alertLabel.Visible = false

	local edges = {
		{ size = UDim2.fromScale(1, 0.18), position = UDim2.fromScale(0, 0), rotation = 90 },
		{ size = UDim2.fromScale(1, 0.18), position = UDim2.fromScale(0, 0.82), rotation = -90 },
		{ size = UDim2.fromScale(0.14, 1), position = UDim2.fromScale(0, 0), rotation = 0 },
		{ size = UDim2.fromScale(0.14, 1), position = UDim2.fromScale(0.86, 0), rotation = 180 },
	}
	for _, edge in edges do
		local frame = UIKit.frame(gui, "Vignette", edge.size, edge.position, C.danger, 0)
		frame.ZIndex = 0
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = edge.rotation
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = frame
		frame.Visible = false
		table.insert(vignette, frame)
	end
end

local function setVignette(on: boolean)
	for _, frame in vignette do
		frame.Visible = on
	end
end

function HUD.setCarrying(info: { rarity: string, biome: string, jackpot: boolean }?)
	carrying = info
	carryFrame.Visible = info ~= nil
	if info then
		local rarity = Config.Rarities[info.rarity] or Config.Rarities.Common
		local stroke = carryFrame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = rarity.color
		end
		UIKit.pop(carryLabel, 0.15)
	else
		chasedBy = nil
		alertLabel.Visible = false
		setVignette(false)
	end
end

function HUD.isCarrying(): boolean
	return carrying ~= nil
end

---------------------------------------------------------------------------
-- Lap timer & floaters & dash
---------------------------------------------------------------------------
local lapFrame: Frame
local lapLabel: TextLabel
local lapBar: Frame
local lapActive = false
local lapStartedAt = 0
local lapProgress = 0
local lapLastAngle = 0
local dashBar: Frame
local dashLabel: TextLabel
local dashReadyAt = 0
local dashCooldown = 1
local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function buildLap()
	lapFrame = UIKit.frame(gui, "Lap", UDim2.fromOffset(300, 58), UDim2.new(0.5, 0, 1, -150), C.panel, 0.08)
	anchored(lapFrame, 0.5, 1)
	HUD.responsive(lapFrame)
	UIKit.corner(lapFrame)
	UIKit.stroke(lapFrame, C.speed, 3)
	lapLabel = UIKit.label(lapFrame, "Text", "", UDim2.new(1, -20, 0, 30), UDim2.fromOffset(10, 4), C.text)
	UIKit.textStroke(lapLabel)
	local track = UIKit.frame(lapFrame, "Track", UDim2.new(1, -24, 0, 12), UDim2.fromOffset(12, 38), C.row)
	UIKit.corner(track, UDim.new(1, 0))
	lapBar = UIKit.frame(track, "Fill", UDim2.fromScale(0, 1), UDim2.new(), C.speed)
	UIKit.corner(lapBar, UDim.new(1, 0))
	lapFrame.Visible = false

	local dash = UIKit.frame(gui, "Dash", UDim2.fromOffset(150, 40), UDim2.new(0, 12, 1, -12), C.panel, 0.15)
	anchored(dash, 0, 1)
	HUD.responsive(dash)
	UIKit.corner(dash)
	UIKit.stroke(dash, C.stroke, 2)
	dashBar = UIKit.frame(dash, "Fill", UDim2.fromScale(1, 1), UDim2.new(), C.speed, 0.6)
	UIKit.corner(dashBar)
	dashLabel = UIKit.label(dash, "Text", "Q  Dash", UDim2.new(1, -16, 1, -8), UDim2.fromOffset(8, 4), C.text)
	UIKit.textStroke(dashLabel)
end

function HUD.dashUsed(cooldown: number)
	dashReadyAt = os.clock() + cooldown
	dashCooldown = cooldown
end

function HUD.floater(text: string, kind: string?)
	local label = UIKit.label(
		gui,
		"Floater",
		text,
		UDim2.fromOffset(220, 40),
		UDim2.new(0.5, math.random(-60, 60), 0.64, 0),
		UIKit.kindColor(kind)
	)
	anchored(label, 0.5, 0.5)
	UIKit.textStroke(label, 2.5)
	UIKit.tween(label, 1.2, { Position = label.Position - UDim2.fromOffset(0, 90) })
	UIKit.fadeText(label, 1.2, 1)
	task.delay(1.25, function()
		label:Destroy()
	end)
end

local function onLapEvent(data: any)
	if type(data) ~= "table" then
		return
	end
	if data.kind == "start" then
		lapActive = true
		lapStartedAt = os.clock()
		lapProgress = 0
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			lapLastAngle =
				math.atan2(root.Position.Z - Config.Training.center.Z, root.Position.X - Config.Training.center.X)
		end
		lapFrame.Visible = true
	elseif data.kind == "complete" then
		local bonus = if type(data.bonus) == "number" then data.bonus else 1
		HUD.floater(`+{Format.short(data.reward or 0)} ⚡`, "speed")
		local bestText = if data.best then " 🏆 New best!" else ""
		HUD.toast(
			`Lap {Format.seconds(data.time or 0)} • x{string.format("%.2f", bonus)} bonus • +{Format.short(
				data.reward or 0
			)} Speed{bestText}`,
			"speed"
		)
		Sounds.play("lap", 1.2)
	elseif data.kind == "cancel" then
		lapActive = false
		lapFrame.Visible = false
		HUD.toast(`Lap cancelled: {data.reason or "left the track"}`, "warn")
	elseif data.kind == "stop" then
		lapActive = false
		lapFrame.Visible = false
	end
end

---------------------------------------------------------------------------
-- Per-frame & periodic updates
---------------------------------------------------------------------------
local function myPlotFloor(): BasePart?
	local map = workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			local floor = plot:FindFirstChild("Floor")
			if floor and floor:IsA("BasePart") then
				return floor
			end
		end
	end
	return nil
end

local currentBiome: string? = nil

local function biomeAt(position: Vector3): Config.BiomeInfo?
	for _, biome in Config.Biomes do
		local offset = Vector3.new(position.X - biome.center.X, 0, position.Z - biome.center.Z)
		if offset.Magnitude <= biome.radius then
			return biome
		end
	end
	return nil
end

local function objectiveText(state: ClientState.State): string
	if carrying then
		return "🏃 Bring the egg home to your nest!"
	end
	if #state.pets == 0 then
		return "🥚 Cross a bridge to 🌼 Meadow Hollow and hold E on an egg"
	end
	if #state.pets >= state.slots then
		return "🐾 Pen full! Fuse, sell or add slots in the 🐾 Pets menu"
	end
	local coinsNeeded, speedNeeded = Progression.rebirthRequirement(state.rebirths)
	if state.coins >= coinsNeeded and state.speed >= speedNeeded then
		return "♻️ You can Rebirth! Open ♻️ Rebirth for a permanent boost"
	end
	for _, biome in Config.Biomes do
		if state.speed < biome.recommendedSpeed then
			return `⚡ Train to {Format.short(biome.recommendedSpeed)} Speed for {biome.icon} {biome.name} (laps or Jog Pad)`
		end
	end
	return "⭐ Fill your 📖 Index, hunt Jackpot Eggs and rare mutations!"
end

local function slowUpdate()
	local state = ClientState.get()
	local text = if ClientState.hasData() then objectiveText(state) else "⏳ Loading your nest..."

	if objectiveLabel.Text ~= text then
		objectiveLabel.Text = text
	end

	local now = workspace:GetServerTimeNow()
	local boosts = {}
	if state.luckUntil > now then
		table.insert(boosts, `🍀 Luck x2 {Format.clock(state.luckUntil - now)}`)
	end
	if state.turboUntil > now then
		table.insert(boosts, `👟 Turbo x2 {Format.clock(state.turboUntil - now)}`)
	end
	local eventKey = workspace:GetAttribute("EventKey")
	local eventEnds = workspace:GetAttribute("EventEndsAt")
	if type(eventKey) == "string" and type(eventEnds) == "number" and eventEnds > now then
		for _, info in Config.Events.list do
			if info.key == eventKey then
				table.insert(boosts, 1, `{info.icon} {info.name} {Format.clock(eventEnds - now)}`)
			end
		end
	end
	if state.friendCount > 0 then
		local bonus = math.floor((Progression.friendMultiplier(state.friendCount) - 1) * 100 + 0.5)
		table.insert(boosts, `👥 Friends +{bonus}%`)
	end
	boostsLabel.Text = table.concat(boosts, "    ")

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local biome = biomeAt(root.Position)
		local key = if biome then biome.key else nil
		if key ~= currentBiome then
			currentBiome = key
			if biome then
				if state.speed < biome.recommendedSpeed then
					HUD.toast(
						`⚠ {biome.icon} {biome.name} recommends {Format.short(biome.recommendedSpeed)} Speed. The guardian may be faster than you!`,
						"warn"
					)
				else
					HUD.toast(`{biome.icon} Welcome to {biome.name}!`, "info")
				end
			end
		end
		if carrying then
			local rarity = Config.Rarities[carrying.rarity] or Config.Rarities.Common
			local floor = myPlotFloor()
			local distance = if floor then math.floor((floor.Position - root.Position).Magnitude) else 0
			local hex = rarity.color:ToHex()
			local name = if carrying.jackpot then `JACKPOT {carrying.rarity}` else carrying.rarity
			carryLabel.Text = `Carrying <font color="#{hex}">{name} Egg</font> • home in {distance} studs`
		end
	end

	if revengeEnds > now then
		revengeFrame.Visible = true
		revengeLabel.Text = `🎯 Net {revengeName} to get your egg back! {math.ceil(revengeEnds - now)}s`
	else
		revengeFrame.Visible = false
	end
end

local function frameUpdate(dt: number)
	local state = ClientState.get()
	local target = state.coins
	if math.abs(target - displayedCoins) < 0.5 then
		displayedCoins = target
	else
		displayedCoins += (target - displayedCoins) * math.min(1, dt * 8)
	end
	local text = Format.money(displayedCoins)
	if coinsValue.Text ~= text then
		coinsValue.Text = text
	end

	local remaining = dashReadyAt - os.clock()
	if remaining > 0 then
		dashBar.Size = UDim2.fromScale(1 - remaining / dashCooldown, 1)
		dashLabel.Text = string.format("Dash %.1fs", remaining)
	else
		dashBar.Size = UDim2.fromScale(1, 1)
		dashLabel.Text = if touchOnly then "Dash ready" else "Q  Dash"
	end

	if lapActive then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local angle =
				math.atan2(root.Position.Z - Config.Training.center.Z, root.Position.X - Config.Training.center.X)
			local delta = angle - lapLastAngle
			if delta > math.pi then
				delta -= math.pi * 2
			elseif delta < -math.pi then
				delta += math.pi * 2
			end
			lapProgress += delta
			lapLastAngle = angle
		end
		local fraction = math.clamp(math.abs(lapProgress) / (math.pi * 2), 0, 1)
		lapBar.Size = UDim2.fromScale(fraction, 1)
		lapLabel.Text = `🏃 Lap {Format.seconds(os.clock() - lapStartedAt)}`
		if fraction >= 1 then
			lapProgress = 0
			lapStartedAt = os.clock()
		end
	end

	if chasedBy then
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * 10)
		alertLabel.TextTransparency = 0.25 * pulse
	end
end

---------------------------------------------------------------------------
function HUD.start()
	gui = makeScreen("NestHeistHUD", 1)
	buildStats()
	buildMenu()
	buildObjective()
	buildToasts()
	buildAlerts()
	buildLap()

	ClientState.onChanged(refreshStats)
	refreshStats(ClientState.get())

	Remotes.Notify.OnClientEvent:Connect(function(text: any, kind: any)
		if type(text) ~= "string" then
			return
		end
		local k = if type(kind) == "string" then kind else "info"
		HUD.toast(text, k)
		if k == "danger" then
			Sounds.play("alarm")
		elseif k == "success" then
			Sounds.play("coin", 1.1)
		elseif k == "warn" then
			Sounds.play("error", 1.4)
		end
	end)
	Remotes.Announce.OnClientEvent:Connect(function(text: any, kind: any)
		if type(text) == "string" then
			HUD.announce(text, if type(kind) == "string" then kind else "info")
			Sounds.play("jackpot")
		end
	end)
	Remotes.Floater.OnClientEvent:Connect(function(text: any, kind: any)
		if type(text) == "string" then
			HUD.floater(text, if type(kind) == "string" then kind else "info")
		end
	end)
	Remotes.Carry.OnClientEvent:Connect(function(state: any, info: any)
		if state == "start" and type(info) == "table" then
			HUD.setCarrying({
				rarity = tostring(info.rarity),
				biome = tostring(info.biome),
				jackpot = info.jackpot == true,
			})
			Sounds.play("grab")
		else
			HUD.setCarrying(nil)
		end
	end)
	Remotes.Guardian.OnClientEvent:Connect(function(kind: any, name: any)
		local guardianName = if type(name) == "string" then name else "The guardian"
		if kind == "chase" then
			chasedBy = guardianName
			alertLabel.Text = `😡 {string.upper(guardianName)} IS CHASING YOU! GET HOME!`
			alertLabel.Visible = true
			setVignette(true)
			Sounds.play("alarm", 0.8)
		else
			chasedBy = nil
			alertLabel.Visible = false
			setVignette(false)
			if kind == "escaped" then
				HUD.toast(`💨 You escaped {guardianName}!`, "success")
			elseif kind == "caught" then
				HUD.toast(`💥 {guardianName} caught you! The egg went back to its nest.`, "danger")
				Sounds.play("caught")
			end
		end
	end)
	Remotes.Revenge.OnClientEvent:Connect(function(thief: any, endsAt: any)
		if typeof(thief) == "Instance" and thief:IsA("Player") and type(endsAt) == "number" then
			revengeName = thief.DisplayName
			revengeEnds = endsAt
		else
			revengeEnds = 0
		end
	end)
	Remotes.Lap.OnClientEvent:Connect(onLapEvent)

	RunService.RenderStepped:Connect(frameUpdate)
	task.spawn(function()
		while true do
			local ok, err = pcall(function(): string?
				slowUpdate()
				return nil
			end)
			if not ok then
				warn("[NestHeist] HUD update error:", err)
			end
			local scale = computeScale()
			for index = #responsiveScales, 1, -1 do
				local s = responsiveScales[index]
				if not s.Parent then
					table.remove(responsiveScales, index)
				elseif math.abs(s.Scale - scale) > 0.001 then
					s.Scale = scale
				end
			end
			task.wait(0.25)
		end
	end)
end

return HUD
