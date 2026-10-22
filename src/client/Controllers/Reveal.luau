--!strict
-- The hatch reveal: the egg wobbles, cracks with a flash, and the new pet spins in a 3D card.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PetLogic = require(ReplicatedStorage.Shared.PetLogic)
local Builders = require(ReplicatedStorage.Shared.Builders)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UIKit = require(script.Parent.UIKit)
local HUD = require(script.Parent.HUD)
local Sounds = require(script.Parent.Sounds)

local C = UIKit.Colors

type HatchData = {
	kind: string,
	size: string,
	mutation: string?,
	lucky: boolean,
	isNew: boolean,
	fused: boolean,
	income: number,
	eggRarity: string,
}

local Reveal = {}

local gui: ScreenGui
local queue: { HatchData } = {}
local showing = false

local function confetti(parent: Instance, colors: { Color3 })
	for _ = 1, 26 do
		local piece = UIKit.frame(
			parent,
			"Confetti",
			UDim2.fromOffset(math.random(8, 14), math.random(8, 14)),
			UDim2.fromScale(0.5, 0.45),
			colors[math.random(1, #colors)]
		)
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Rotation = math.random(0, 360)
		piece.ZIndex = 20
		local angle = math.random() * math.pi * 2
		local distance = math.random(160, 340)
		UIKit.tween(piece, 1.1, {
			Position = UDim2.new(0.5, math.cos(angle) * distance, 0.45, math.sin(angle) * distance + 120),
			Rotation = piece.Rotation + math.random(-360, 360),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(1.2, function()
			piece:Destroy()
		end)
	end
end

local function present(
	data: HatchData,
	overlay: Frame,
	info: Config.PetInfo,
	rarity: Config.RarityInfo,
	eggRarity: Config.RarityInfo,
	scale: number
)
	local stage = UIKit.frame(overlay, "Stage", UDim2.fromOffset(420, 520), UDim2.fromScale(0.5, 0.5), C.panel, 1)
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	HUD.responsive(stage)

	-- 1) Wobbling egg
	local egg = UIKit.frame(stage, "Egg", UDim2.fromOffset(130, 165), UDim2.fromScale(0.5, 0.45), eggRarity.color)
	egg.AnchorPoint = Vector2.new(0.5, 0.5)
	UIKit.corner(egg, UDim.new(0.5, 0))
	UIKit.stroke(egg, C.stroke, 4)
	UIKit.gradient(egg, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	local band = UIKit.frame(egg, "Band", UDim2.new(1, 0, 0, 16), UDim2.fromScale(0, 0.55), Color3.new(1, 1, 1), 0.3)
	band.BorderSizePixel = 0
	Sounds.play("grab", 0.8)
	for i = 1, 7 do
		local angle = (if i % 2 == 0 then 1 else -1) * (6 + i * 2)
		UIKit.tween(egg, 0.09, { Rotation = angle })
		task.wait(0.11 - i * 0.006)
	end
	if data.lucky then
		-- Lucky hatch: the egg shifts colour to the upgraded rarity.
		UIKit.tween(egg, 0.25, { BackgroundColor3 = rarity.color })
		HUD.floater("🍀 LUCKY HATCH!", "success")
		task.wait(0.3)
	end
	UIKit.tween(egg, 0.12, { Size = UDim2.fromOffset(170, 210), Rotation = 0 })
	task.wait(0.12)

	-- 2) Flash
	local flash = UIKit.frame(overlay, "Flash", UDim2.fromScale(1, 1), UDim2.new(), Color3.new(1, 1, 1), 0)
	flash.ZIndex = 30
	egg:Destroy()
	Sounds.play("hatch")
	UIKit.tween(flash, 0.5, { BackgroundTransparency = 1 })
	task.delay(0.55, function()
		flash:Destroy()
	end)
	confetti(overlay, { rarity.color, C.coins, Color3.new(1, 1, 1), C.feathers })

	-- 3) Card with the pet in 3D
	local card = UIKit.frame(stage, "Card", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), C.panel, 0.02)
	card.AnchorPoint = Vector2.new(0.5, 0.5) -- pop grows from the centre
	UIKit.corner(card, UDim.new(0, 20))
	local stroke = UIKit.stroke(card, rarity.color, 5)
	stroke.Transparency = 0
	UIKit.pop(card, 0.2)

	local rarityText = UIKit.label(
		card,
		"Rarity",
		if data.fused then "🧪 FUSED! " .. string.upper(info.rarity) else string.upper(info.rarity) .. "!",
		UDim2.new(1, -20, 0, 50),
		UDim2.fromOffset(10, 12),
		rarity.color
	)
	UIKit.textStroke(rarityText, 3)

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.Size = UDim2.new(1, -40, 0, 250)
	viewport.Position = UDim2.fromOffset(20, 66)
	viewport.BackgroundColor3 = rarity.color:Lerp(Color3.new(0, 0, 0), 0.55)
	viewport.BackgroundTransparency = 0.2
	viewport.Ambient = Color3.fromRGB(170, 170, 185)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.LightDirection = Vector3.new(-0.4, -1, 0.6) -- from the camera side, onto the pet's face
	viewport.Parent = card
	UIKit.corner(viewport, UDim.new(0, 16))
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local model = Builders.pet(data.kind, scale, data.mutation, CFrame.new())
	model.Parent = viewport
	local height = 3.4 * scale
	local distance = 7.5 + 4.2 * scale
	camera.CFrame = CFrame.lookAt(Vector3.new(0, height * 0.75, -distance), Vector3.new(0, height * 0.45, 0))

	local name = UIKit.label(
		card,
		"Name",
		PetLogic.describe({ id = "", kind = data.kind, size = data.size, mutation = data.mutation }),
		UDim2.new(1, -30, 0, 40),
		UDim2.fromOffset(15, 324),
		C.text
	)
	UIKit.textStroke(name, 2.5)
	local tags = {}
	if data.isNew then
		table.insert(tags, "✨ NEW PET!")
	end
	if data.lucky then
		table.insert(tags, "🍀 LUCKY!")
	end
	if data.mutation then
		table.insert(tags, `💎 {data.mutation}`)
	end
	local detail = UIKit.label(
		card,
		"Detail",
		if #tags > 0 then table.concat(tags, "   ") else `{data.size} size`,
		UDim2.new(1, -30, 0, 26),
		UDim2.fromOffset(15, 366),
		C.feathers,
		UIKit.BodyFont
	)
	UIKit.textStroke(detail, 1.5)
	local income = UIKit.label(
		card,
		"Income",
		`+{Format.money(data.income)}/s`,
		UDim2.new(1, -30, 0, 36),
		UDim2.fromOffset(15, 396),
		C.coins
	)
	UIKit.textStroke(income, 2.5)

	local done = false
	UIKit.button(card, "Ok", "Awesome!", UDim2.fromOffset(200, 50), UDim2.new(0.5, -100, 1, -64), C.button, function()
		done = true
	end)

	local spin = 0
	local connection = RunService.RenderStepped:Connect(function(dt: number)
		spin += dt * 1.2
		model:PivotTo(CFrame.Angles(0, spin, 0))
	end)

	local started = os.clock()
	while not done and os.clock() - started < 5 do
		task.wait(0.05)
	end
	connection:Disconnect()
end

local function show(data: HatchData)
	local info = Config.PetByKey[data.kind]
	if not info then
		return
	end
	local rarity = Config.Rarities[info.rarity]
	local eggRarity = Config.Rarities[data.eggRarity] or rarity
	local sizeInfo = PetLogic.sizeInfo(data.size)
	local scale = if sizeInfo then sizeInfo.scale else 1

	-- Not Active: the player can keep moving and looking around while the card is up.
	local overlay = UIKit.frame(gui, "Overlay", UDim2.fromScale(1, 1), UDim2.new(), Color3.new(0, 0, 0), 1)
	overlay.Active = false
	UIKit.tween(overlay, 0.3, { BackgroundTransparency = 0.6 })
	local ok, err = pcall(function(): string?
		present(data, overlay, info, rarity, eggRarity, scale)
		return nil
	end)
	if not ok then
		warn("[NestHeist] Hatch reveal failed:", err)
	end
	UIKit.tween(overlay, 0.2, { BackgroundTransparency = 1 })
	task.wait(0.15)
	overlay:Destroy()
end

-- Mid-heist, don't cover the screen: wait until the egg is home, or fall back to a toast.
local function compact(data: HatchData)
	HUD.toast(
		`🐣 Hatched {PetLogic.describe({ id = "", kind = data.kind, size = data.size, mutation = data.mutation })}! +{Format.money(
			data.income
		)}/s`,
		"rare"
	)
	Sounds.play("hatch")
end

local function runQueue()
	showing = true
	while #queue > 0 do
		local data = table.remove(queue, 1)
		if data then
			local waited = 0
			while HUD.isCarrying() and waited < 20 do
				task.wait(0.25)
				waited += 0.25
			end
			local ok, err = pcall(function(): string?
				if HUD.isCarrying() then
					compact(data)
				else
					show(data)
				end
				return nil
			end)
			if not ok then
				warn("[NestHeist] Hatch reveal failed:", err)
			end
		end
	end
	showing = false
end

function Reveal.start()
	gui = HUD.makeScreen("NestHeistReveal", 10)
	Remotes.Hatch.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" or type(payload.kind) ~= "string" then
			return
		end
		table.insert(queue, {
			kind = payload.kind,
			size = if type(payload.size) == "string" then payload.size else "Normal",
			mutation = if type(payload.mutation) == "string" then payload.mutation else nil,
			lucky = payload.lucky == true,
			isNew = payload.isNew == true,
			fused = payload.fused == true,
			income = if type(payload.income) == "number" then payload.income else 0,
			eggRarity = if type(payload.eggRarity) == "string" then payload.eggRarity else "Common",
		})
		if not showing then
			task.spawn(runQueue)
		end
	end)
end

return Reveal
