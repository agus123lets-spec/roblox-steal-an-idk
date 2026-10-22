--!strict
-- Purchases (coins and feathers), selling pets and cosmetic trails.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PetLogic = require(ReplicatedStorage.Shared.PetLogic)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerService = require(script.Parent.PlayerService)
local ToolService = require(script.Parent.ToolService)
local PlotService = require(script.Parent.PlotService)

type Session = PlayerService.Session

local ShopService = {}

local function trailInfo(key: string): Config.TrailInfo?
	for _, info in Config.Trails do
		if info.key == key then
			return info
		end
	end
	return nil
end

function ShopService.applyTrail(player: Player)
	local session = PlayerService.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not session or not root then
		return
	end
	for _, name in { "NestTrail", "NestTrailTop", "NestTrailBottom" } do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local info = trailInfo(session.data.equippedTrail)
	if not info then
		return
	end
	local top = Instance.new("Attachment")
	top.Name = "NestTrailTop"
	top.Position = Vector3.new(0, 0.9, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "NestTrailBottom"
	bottom.Position = Vector3.new(0, -0.9, 0)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "NestTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(info.c1, info.c2)
	trail.Lifetime = 0.45
	trail.LightEmission = 0.6
	trail.FaceCamera = true
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.WidthScale = NumberSequence.new(1, 0.1)
	trail.Parent = root
end

local function themeInfo(key: string): Config.ThemeInfo?
	for _, info in Config.Themes do
		if info.key == key then
			return info
		end
	end
	return nil
end

local function buy(session: Session, itemId: string): (boolean, string)
	local data = session.data
	local now = PlayerService.now()

	if itemId == "Shoes" then
		local nextShoes = Config.Shoes[data.shoesLevel + 1]
		if not nextShoes then
			return false, "You already own the best shoes!"
		end
		if not PlayerService.trySpend(session, nextShoes.cost) then
			return false, `You need {Format.money(nextShoes.cost)} for {nextShoes.name}.`
		end
		data.shoesLevel += 1
		return true, `👟 {nextShoes.name}! Training now gives x{nextShoes.mult} Speed.`
	elseif itemId == "Slot" then
		local cost = PetLogic.slotCost(data.slots)
		if not cost then
			return false, "Your pen is already the biggest it can be!"
		end
		if not PlayerService.trySpend(session, cost) then
			return false, `You need {Format.money(cost)} for another pen slot.`
		end
		data.slots += 1
		PlayerService.petsChanged(session)
		return true, `🐾 Pen expanded to {data.slots} slots!`
	elseif itemId == "Tool:Slime" then
		if data.tools.Slime then
			return false, "You already own the Slime Puddle."
		end
		if not PlayerService.trySpend(session, Config.Tools.Slime.cost) then
			return false, `You need {Format.money(Config.Tools.Slime.cost)} for the Slime Puddle.`
		end
		data.tools.Slime = true
		ToolService.giveTools(session.player)
		return true, "🟢 Slime Puddle added to your backpack!"
	end

	for _, item in Config.FeatherShop do
		if item.id == itemId then
			if not PlayerService.trySpendFeathers(session, item.cost) then
				return false,
					`You need {item.cost} 🪶 feathers. Get some when your eggs are stolen, or by pulling off underdog heists!`
			end
			if itemId == "Boost:Luck" then
				session.luckUntil = math.max(session.luckUntil, now) + item.duration
			else
				session.turboUntil = math.max(session.turboUntil, now) + item.duration
			end
			return true, `✨ {item.name} activated!`
		end
	end

	local themeKey = string.match(itemId, "^Theme:(.+)$")
	if themeKey then
		if themeKey == "Classic" then
			data.equippedTheme = ""
			PlotService.applyTheme(session.player)
			return true, "🏡 Classic nest restored."
		end
		local info = themeInfo(themeKey)
		if not info then
			return false, "Unknown theme."
		end
		if not data.themes[themeKey] then
			if not PlayerService.trySpendFeathers(session, info.cost) then
				return false, `You need {info.cost} 🪶 feathers for {info.name}.`
			end
			data.themes[themeKey] = true
		end
		data.equippedTheme = themeKey
		PlotService.applyTheme(session.player)
		return true, `🏡 {info.name} applied to your nest!`
	end

	local trailKey = string.match(itemId, "^Trail:(.+)$")
	if trailKey then
		local info = trailInfo(trailKey)
		if not info then
			return false, "Unknown trail."
		end
		if data.trails[trailKey] then
			data.equippedTrail = if data.equippedTrail == trailKey then "" else trailKey
			ShopService.applyTrail(session.player)
			return true, if data.equippedTrail == "" then "Trail unequipped." else `{info.name} equipped!`
		end
		if not PlayerService.trySpendFeathers(session, info.cost) then
			return false, `You need {info.cost} 🪶 feathers for {info.name}.`
		end
		data.trails[trailKey] = true
		data.equippedTrail = trailKey
		ShopService.applyTrail(session.player)
		return true, `{info.name} unlocked and equipped!`
	end

	return false, "Unknown item."
end

function ShopService.start()
	Remotes.Purchase.OnServerInvoke = function(player: Player, itemId: any): (boolean, string)
		local session = PlayerService.get(player)
		if not session or type(itemId) ~= "string" then
			return false, "Not ready yet."
		end
		local ok, message = buy(session, itemId)
		session.dirty = true
		return ok, message
	end

	Remotes.SellPet.OnServerInvoke = function(player: Player, petId: any): (boolean, string)
		local session = PlayerService.get(player)
		if not session or type(petId) ~= "string" then
			return false, "Not ready yet."
		end
		local pet = PlayerService.removePet(session, petId)
		if not pet then
			return false, "That pet is already gone."
		end
		local value = PetLogic.sellValue(pet)
		PlayerService.addCoins(session, value)
		return true, `Sold {PetLogic.describe(pet)} for {Format.money(value)}.`
	end

	PlayerService.onCharacterSpawned(function(session: Session, character: Model)
		character:WaitForChild("HumanoidRootPart", 10)
		ShopService.applyTrail(session.player)
	end)
end

return ShopService
