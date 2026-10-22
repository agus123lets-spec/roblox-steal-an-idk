--!strict
-- The heart of the game: eggs in nests, carrying, dropping, incubating, hatching,
-- stealing from other players, revenge and Jackpot Egg events.

local HttpService: HttpService = game:GetService("HttpService")
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PetLogic = require(ReplicatedStorage.Shared.PetLogic)
local Builders = require(ReplicatedStorage.Shared.Builders)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerService = require(script.Parent.PlayerService)
local PlotService = require(script.Parent.PlotService)
local Loop = require(script.Parent.Loop)
local EventState = require(script.Parent.EventState)
local RewardService = require(script.Parent.RewardService)

type Session = PlayerService.Session
type Plot = PlotService.Plot

export type Nest = {
	biome: string,
	index: number,
	spot: CFrame,
	egg: Egg?,
	respawnAt: number,
}

export type Egg = {
	id: number,
	biome: string,
	rarity: string,
	jackpot: boolean,
	model: Model,
	shell: BasePart,
	gui: BillboardGui,
	title: TextLabel,
	subtitle: TextLabel,
	state: string, -- "nest" | "carried" | "dropped" | "incubating" | "gone"
	nest: Nest?,
	carrier: Player?,
	lastHolder: Player?,
	stolenFrom: Player?,
	baseOwner: Player?,
	incubatorPlot: Plot?,
	incubatorIndex: number,
	hatchAt: number,
	remaining: number,
	dropExpires: number,
	feathersPaid: boolean,
	prompt: ProximityPrompt?,
	weld: Weld?,
	beam: BasePart?,
	warnedAt: number,
	underdogPaid: boolean,
	recoveredPaid: boolean,
}

local EggService = {}

local eggsFolder: Folder
local nests: { Nest } = {}
local eggs: { [number]: Egg } = {}
local carried: { [Player]: Egg } = {}
local incubators: { [Plot]: { [number]: Egg } } = {}
local nextId = 0
local random = Random.new()

local function roll(): number
	return random:NextNumber()
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rarityInfo(egg: Egg): Config.RarityInfo
	return Config.Rarities[egg.rarity] or Config.Rarities.Common
end

local function eggTitle(egg: Egg): string
	return if egg.jackpot then `⭐ JACKPOT {egg.rarity} Egg ⭐` else `{egg.rarity} Egg`
end

local function setLabel(egg: Egg, title: string, subtitle: string)
	-- Incubating eggs are described by the incubator's own label instead.
	local visible = egg.state ~= "incubating"
	if egg.gui.Enabled ~= visible then
		egg.gui.Enabled = visible
	end
	if egg.title.Text ~= title then
		egg.title.Text = title
	end
	if egg.subtitle.Text ~= subtitle then
		egg.subtitle.Text = subtitle
	end
end

---------------------------------------------------------------------------
-- Prompts
---------------------------------------------------------------------------
local function clearPrompt(egg: Egg)
	if egg.prompt then
		egg.prompt:Destroy()
		egg.prompt = nil
	end
end

-- A fresh prompt per state, so client-side tweaks (hiding your own steal prompt) never go stale.
local function setPrompt(egg: Egg, action: string, holdDuration: number, hideForUserId: number?)
	clearPrompt(egg)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = eggTitle(egg)
	prompt.HoldDuration = holdDuration
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	if hideForUserId then
		prompt:SetAttribute("HideForUserId", hideForUserId)
	end
	prompt.Triggered:Connect(function(player: Player)
		EggService.onPromptTriggered(egg, player)
	end)
	prompt.Parent = egg.shell
	egg.prompt = prompt
end

---------------------------------------------------------------------------
-- Egg lifecycle
---------------------------------------------------------------------------
local function createEgg(biome: string, rarity: string, jackpot: boolean): Egg
	nextId += 1
	local model = Builders.egg(rarity, biome, jackpot)
	local shell = model.PrimaryPart :: BasePart
	local gui = Builders.billboard(shell, Vector3.new(0, if jackpot then 3.6 else 3, 0), UDim2.fromOffset(190, 46), 80)
	local color = (Config.Rarities[rarity] or Config.Rarities.Common).color
	local title =
		Builders.text(gui, "Title", "", UDim2.fromScale(1, 0.58), UDim2.fromScale(0, 0), color, Enum.Font.FredokaOne)
	local subtitle = Builders.text(
		gui,
		"Subtitle",
		"",
		UDim2.fromScale(1, 0.42),
		UDim2.fromScale(0, 0.58),
		Color3.new(1, 1, 1),
		Enum.Font.GothamBold
	)
	local egg: Egg = {
		id = nextId,
		biome = biome,
		rarity = rarity,
		jackpot = jackpot,
		model = model,
		shell = shell,
		gui = gui,
		title = title,
		subtitle = subtitle,
		state = "new",
		nest = nil,
		carrier = nil,
		lastHolder = nil,
		stolenFrom = nil,
		baseOwner = nil,
		incubatorPlot = nil,
		incubatorIndex = 0,
		hatchAt = 0,
		remaining = 0,
		dropExpires = 0,
		feathersPaid = false,
		prompt = nil,
		weld = nil,
		beam = nil,
		warnedAt = 0,
		underdogPaid = false,
		recoveredPaid = false,
	}
	eggs[egg.id] = egg
	model.Parent = eggsFolder
	return egg
end

local function anchorAt(egg: Egg, cf: CFrame)
	if egg.weld then
		egg.weld:Destroy()
		egg.weld = nil
	end
	egg.shell.Anchored = true
	egg.model:PivotTo(cf)
end

local function removeBeam(egg: Egg)
	if egg.beam then
		egg.beam:Destroy()
		egg.beam = nil
	end
end

local function freeIncubator(egg: Egg)
	local plot = egg.incubatorPlot
	if plot then
		local slots = incubators[plot]
		if slots and slots[egg.incubatorIndex] == egg then
			slots[egg.incubatorIndex] = nil
		end
		local label = plot.incubatorLabels[egg.incubatorIndex]
		if label then
			label.Text = "Empty"
			label.TextColor3 = Color3.new(1, 1, 1)
		end
	end
	egg.incubatorPlot = nil
	egg.incubatorIndex = 0
end

-- Stops any carrying. Safe to call when the egg isn't carried.
local function detach(egg: Egg)
	local carrier = egg.carrier
	if carrier then
		if carried[carrier] == egg then
			carried[carrier] = nil
		end
		carrier:SetAttribute("Carrying", nil)
		if carrier.Parent then
			Remotes.Carry:FireClient(carrier, "end", nil)
		end
		egg.carrier = nil
	end
	if egg.weld then
		egg.weld:Destroy()
		egg.weld = nil
	end
	egg.shell.Anchored = true
end

local function destroyEgg(egg: Egg)
	if egg.state == "gone" then
		return
	end
	detach(egg)
	clearPrompt(egg)
	removeBeam(egg)
	freeIncubator(egg)
	local nest = egg.nest
	if nest and nest.egg == egg then
		nest.egg = nil
	end
	egg.state = "gone"
	eggs[egg.id] = nil
	egg.model:Destroy()
end

local function updateStealPrompt(egg: Egg)
	local owner = egg.baseOwner
	if egg.state ~= "incubating" or not owner then
		return
	end
	if PlotService.isShielded(owner) then
		clearPrompt(egg)
	elseif not egg.prompt then
		setPrompt(egg, "Steal Egg", Config.Steal.stealHold, owner.UserId)
	end
end

local function freeIncubatorIndex(plot: Plot): number?
	local slots = incubators[plot]
	for i = 1, #plot.incubatorSpots do
		if slots[i] == nil then
			return i
		end
	end
	return nil
end

local function incubate(egg: Egg, owner: Player, plot: Plot, index: number, duration: number)
	detach(egg)
	clearPrompt(egg)
	egg.state = "incubating"
	egg.incubatorPlot = plot
	egg.incubatorIndex = index
	egg.baseOwner = owner
	egg.hatchAt = now() + duration
	egg.remaining = 0
	incubators[plot][index] = egg
	local label = plot.incubatorLabels[index]
	if label then
		label.Text = `{eggTitle(egg)} • {math.ceil(duration)}s`
		label.TextColor3 = rarityInfo(egg).color
	end
	anchorAt(egg, plot.incubatorSpots[index].CFrame)
	setLabel(egg, eggTitle(egg), `Hatching in {math.ceil(duration)}s`)
	updateStealPrompt(egg)
end

local function addJackpotBeam(egg: Egg, position: Vector3)
	if egg.beam then
		return
	end
	local beam = Builders.cylinder(
		eggsFolder,
		"JackpotBeam",
		160,
		3,
		CFrame.new(position + Vector3.new(0, 80, 0)),
		Color3.fromRGB(255, 214, 70),
		Enum.Material.Neon
	)
	beam.Transparency = 0.55
	beam.CastShadow = false
	Builders.noCollide(beam)
	egg.beam = beam
end

local function placeInNest(egg: Egg, nest: Nest)
	detach(egg)
	nest.egg = egg
	egg.nest = nest
	egg.state = "nest"
	egg.baseOwner = nil
	egg.stolenFrom = nil
	egg.lastHolder = nil
	anchorAt(egg, nest.spot)
	setLabel(egg, eggTitle(egg), Config.BiomeByKey[nest.biome].name)
	setPrompt(egg, "Grab Egg", Config.Steal.grabHold, nil)
	if egg.jackpot then
		addJackpotBeam(egg, nest.spot.Position)
	end
end

-- Sends a lost egg back: to the nest it was stolen from, else its wild nest, else gone.
local function returnToOrigin(egg: Egg)
	if egg.state == "gone" then
		return
	end
	-- The engine can delete a carried egg (e.g. its carrier fell into the void); just forget it.
	if not egg.shell:IsDescendantOf(workspace) then
		destroyEgg(egg)
		return
	end
	local remaining = egg.remaining
	detach(egg)
	clearPrompt(egg)
	freeIncubator(egg)

	local owner = egg.baseOwner
	local ownerSession = if owner and owner.Parent then PlayerService.get(owner) else nil
	if owner and ownerSession then
		local plot = PlotService.getPlot(owner)
		local index = if plot then freeIncubatorIndex(plot) else nil
		if plot and index then
			local full = rarityInfo(egg).hatchTime
			incubate(egg, owner, plot, index, if remaining > 0 then math.min(remaining, full) else full)
			egg.stolenFrom = nil
			PlayerService.clearRevenge(ownerSession)
			PlayerService.notify(owner, `Your {egg.rarity} egg flew back home!`, "success")
			return
		end
	end

	local nest = egg.nest
	if nest and (nest.egg == nil or nest.egg == egg) then
		placeInNest(egg, nest)
		return
	end
	destroyEgg(egg)
end

local function spawnInNest(nest: Nest, rarity: string, jackpot: boolean): Egg
	local egg = createEgg(nest.biome, rarity, jackpot)
	placeInNest(egg, nest)
	return egg
end

local function attachTo(egg: Egg, session: Session): boolean
	local root = PlayerService.rootOf(session.player)
	if not root then
		return false
	end
	clearPrompt(egg)
	removeBeam(egg)
	-- Weld first, then unanchor in the same frame so the egg never falls.
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = egg.shell
	weld.C0 = CFrame.new(0, Config.Steal.carryHeight, 0)
	weld.Parent = egg.shell
	egg.shell.Anchored = false
	egg.weld = weld
	egg.state = "carried"
	egg.carrier = session.player
	egg.lastHolder = session.player
	carried[session.player] = egg
	session.player:SetAttribute("Carrying", egg.rarity)
	setLabel(egg, eggTitle(egg), session.player.DisplayName)
	Remotes.Carry:FireClient(session.player, "start", { rarity = egg.rarity, biome = egg.biome, jackpot = egg.jackpot })
	return true
end

local function groundBelow(position: Vector3): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { eggsFolder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	local result = workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -40, 0), params)
	return if result then result.Position else nil
end

local function dropEgg(egg: Egg, position: Vector3)
	local holder = egg.carrier
	detach(egg)
	local ground = groundBelow(position)
	if not ground then
		returnToOrigin(egg)
		return
	end
	egg.state = "dropped"
	egg.lastHolder = holder
	egg.dropExpires = now() + Config.Steal.droppedLifetime
	anchorAt(egg, CFrame.new(ground + Vector3.new(0, 1.6, 0)))
	setLabel(egg, eggTitle(egg), "Dropped! Grab it!")
	setPrompt(egg, "Grab Egg", Config.Steal.grabHold, nil)
end

---------------------------------------------------------------------------
-- Stealing
---------------------------------------------------------------------------
local function theft(egg: Egg, thief: Session, victim: Player)
	if victim == thief.player then
		return
	end
	-- The original owner keeps their claim even if the egg changes hands again.
	egg.stolenFrom = egg.stolenFrom or victim
	local feathers = rarityInfo(egg).feathers * (if egg.jackpot then 2 else 1)
	local victimSession = PlayerService.get(victim)
	if victimSession then
		local bonusText = ""
		if not egg.feathersPaid then
			egg.feathersPaid = true
			PlayerService.addFeathers(victimSession, feathers)
			bonusText = ` (+{feathers} 🪶)`
		end
		PlayerService.setRevenge(victimSession, thief.player)
		PlayerService.notify(
			victim,
			`🚨 {thief.player.DisplayName} stole your {egg.rarity} egg! Net them within {Config.Steal.revengeDuration}s to get it back.{bonusText}`,
			"danger"
		)
		if not egg.underdogPaid and victimSession.data.speed > thief.data.speed * Config.Steal.underdogRatio then
			egg.underdogPaid = true
			PlayerService.addFeathers(thief, feathers)
			PlayerService.notify(thief.player, `Underdog heist! +{feathers} 🪶`, "rare")
		end
	end
	PlayerService.notify(
		thief.player,
		`You swiped {victim.DisplayName}'s egg! Get it home before they catch you!`,
		"warn"
	)
	Remotes.FX:FireAllClients("Steal", egg.shell.Position)
end

local function deposit(egg: Egg, session: Session, plot: Plot, index: number)
	local stolen = egg.stolenFrom ~= nil and egg.stolenFrom ~= session.player
	local full = rarityInfo(egg).hatchTime
	local duration = if egg.remaining > 0 then math.min(egg.remaining, full) else full
	duration = math.max(duration, 2)
	egg.stolenFrom = nil
	incubate(egg, session.player, plot, index, duration)
	if stolen then
		session.data.stats.stolen += 1
		RewardService.progress(session, "Steal", 1)
		PlayerService.notify(
			session.player,
			`Heist complete! The {egg.rarity} egg hatches in {math.ceil(duration)}s.`,
			"success"
		)
	else
		PlayerService.notify(
			session.player,
			`{eggTitle(egg)} is incubating! Hatches in {math.ceil(duration)}s.`,
			"success"
		)
	end
	session.dirty = true
	Remotes.FX:FireAllClients("Deposit", egg.shell.Position)
end

---------------------------------------------------------------------------
-- Hatching
---------------------------------------------------------------------------
local function hatch(egg: Egg, session: Session, silent: boolean)
	local luck = PlayerService.luckOf(session)
	local kind, size, mutation, lucky = PetLogic.rollHatch(roll, egg.biome, egg.rarity, luck, egg.jackpot)
	local pet: PetLogic.PetData =
		{ id = HttpService:GenerateGUID(false), kind = kind, size = size, mutation = mutation }
	local isNew = not session.data.index[kind]
	local position = egg.shell.Position
	destroyEgg(egg)
	if not PlayerService.addPet(session, pet) then
		return
	end
	session.data.stats.hatched += 1
	RewardService.progress(session, "Hatch", 1)
	local hatchedInfo = Config.PetByKey[kind]
	if hatchedInfo and Config.Rarities[hatchedInfo.rarity].order >= 3 then
		RewardService.progress(session, "RareHatch", 1)
	end
	if silent then
		return
	end
	local info = Config.PetByKey[kind]
	local rarity = Config.Rarities[info.rarity]
	Remotes.Hatch:FireClient(session.player, {
		kind = kind,
		size = size,
		mutation = mutation,
		lucky = lucky,
		isNew = isNew,
		income = PetLogic.income(pet),
		eggRarity = egg.rarity,
	})
	Remotes.FX:FireAllClients("Hatch", position, rarity.color)
	if rarity.order >= 4 or mutation ~= nil or size == "Huge" or size == "Titanic" then
		PlayerService.announce(`🎉 {session.player.DisplayName} hatched a {PetLogic.describe(pet)}!`, "rare")
	end
end

---------------------------------------------------------------------------
-- Prompt handling
---------------------------------------------------------------------------
function EggService.onPromptTriggered(egg: Egg, player: Player)
	if eggs[egg.id] ~= egg then
		return
	end
	local session = PlayerService.get(player)
	local root = PlayerService.rootOf(player)
	if not session or not root then
		return
	end
	if carried[player] then
		PlayerService.notify(player, "You can only carry one egg at a time!", "warn")
		return
	end
	if PlayerService.isStunned(session) or (root.Position - egg.shell.Position).Magnitude > 18 then
		return
	end
	if not PlotService.getPlot(player) then
		PlayerService.notify(
			player,
			"You need a nest to bring eggs home to. This server is full, try another one!",
			"warn"
		)
		return
	end

	if egg.state == "nest" then
		local nest = egg.nest
		if nest and nest.egg == egg then
			nest.egg = nil
			local biome = Config.BiomeByKey[nest.biome]
			nest.respawnAt = now()
				+ (biome.respawnMin + roll() * (biome.respawnMax - biome.respawnMin)) * EventState.factor("respawn")
		end
		attachTo(egg, session)
		if egg.jackpot then
			PlayerService.announce(`⭐ {player.DisplayName} grabbed the Jackpot Egg! Stop them!`, "rare")
		end
	elseif egg.state == "dropped" then
		local previous = egg.lastHolder
		if egg.stolenFrom == player then
			egg.stolenFrom = nil
			attachTo(egg, session)
			PlayerService.clearRevenge(session)
			if egg.recoveredPaid then
				PlayerService.notify(player, "🎯 Revenge! You got your egg back!", "success")
			else
				egg.recoveredPaid = true
				PlayerService.addFeathers(session, Config.Steal.recoverFeathers)
				PlayerService.notify(
					player,
					`🎯 Revenge! You got your egg back! (+{Config.Steal.recoverFeathers} 🪶)`,
					"success"
				)
			end
		else
			attachTo(egg, session)
			if previous and previous ~= player and previous.Parent then
				theft(egg, session, previous)
			end
		end
	elseif egg.state == "incubating" then
		local owner = egg.baseOwner
		if not owner or owner == player then
			return
		end
		if PlotService.isShielded(owner) then
			PlayerService.notify(player, "That nest is shielded! Come back when the shield drops.", "warn")
			return
		end
		local ownerSession = PlayerService.get(owner)
		if ownerSession then
			local allowed, reason = PlayerService.canTarget(session, ownerSession)
			if not allowed then
				PlayerService.notify(player, reason or "You can't steal that egg.", "warn")
				return
			end
		end
		egg.remaining = math.max(egg.hatchAt - now(), 0)
		freeIncubator(egg)
		attachTo(egg, session)
		theft(egg, session, owner)
	end
end

---------------------------------------------------------------------------
-- Public API for other services
---------------------------------------------------------------------------
function EggService.isCarrying(player: Player): boolean
	return carried[player] ~= nil
end

function EggService.isCarryingJackpot(player: Player): boolean
	local egg = carried[player]
	return egg ~= nil and egg.jackpot
end

-- Netted: the carrier drops their egg on the ground for anyone to grab.
function EggService.knockLoose(target: Player): boolean
	local egg = carried[target]
	local root = PlayerService.rootOf(target)
	if not egg then
		return false
	end
	dropEgg(egg, if root then root.Position else egg.shell.Position)
	return true
end

-- Caught by a guardian: the egg flies back where it came from.
function EggService.guardianCatch(player: Player)
	local egg = carried[player]
	if egg then
		returnToOrigin(egg)
	end
end

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------
local function loadNests()
	local map = workspace:FindFirstChild("Map")
	local biomes = map and map:FindFirstChild("Biomes")
	if not biomes then
		error("[NestHeist] Workspace.Map.Biomes is missing")
	end
	for _, biome in Config.Biomes do
		local biomeModel = biomes:FindFirstChild(biome.key)
		local nestFolder = biomeModel and biomeModel:FindFirstChild("Nests")
		if nestFolder then
			for _, nestModel in nestFolder:GetChildren() do
				local spot = nestModel:FindFirstChild("Spot")
				if nestModel:IsA("Model") and spot and spot:IsA("BasePart") then
					local index = nestModel:GetAttribute("Index")
					table.insert(nests, {
						biome = biome.key,
						index = if type(index) == "number" then index else #nests + 1,
						spot = spot.CFrame,
						egg = nil,
						respawnAt = 0,
					})
				end
			end
		end
	end
end

local function spawnJackpot()
	local weights = {}
	for i, biome in Config.Biomes do
		weights[i] = biome.jackpotWeight
	end
	local biome = Config.Biomes[PetLogic.pickIndex(roll, weights)]
	local candidates: { Nest } = {}
	for _, nest in nests do
		if nest.biome == biome.key and (nest.egg == nil or (nest.egg :: Egg).state == "nest") then
			table.insert(candidates, nest)
		end
	end
	if #candidates == 0 then
		return
	end
	local nest = candidates[random:NextInteger(1, #candidates)]
	local existing = nest.egg
	if existing then
		destroyEgg(existing)
	end
	spawnInNest(nest, PetLogic.rollJackpotRarity(roll), true)
	PlayerService.announce(`⭐ A JACKPOT EGG appeared in {biome.icon} {biome.name}! Follow the golden beam!`, "rare")
end

local function depositTick()
	local t = now()
	for player, egg in carried do
		local session = PlayerService.get(player)
		local root = PlayerService.rootOf(player)
		local plot = PlotService.getPlot(player)
		if session and root and plot and PlotService.isInside(plot, root.Position, 1) then
			local index = freeIncubatorIndex(plot)
			if index then
				deposit(egg, session, plot, index)
			elseif t - egg.warnedAt > 4 then
				egg.warnedAt = t
				PlayerService.notify(player, "All your incubators are busy! Wait for one to hatch.", "warn")
			end
		end
	end
end

local function hatchTick()
	local t = now()
	-- Forget eggs the engine deleted (e.g. carried into the void).
	for _, egg in eggs do
		if egg.state ~= "gone" and not egg.shell:IsDescendantOf(workspace) then
			destroyEgg(egg)
		end
	end
	-- Incubators
	for plot, slots in incubators do
		for index, egg in slots do
			local owner = egg.baseOwner
			local session = if owner then PlayerService.get(owner) else nil
			local label = plot.incubatorLabels[index]
			if t >= egg.hatchAt then
				if session and PlayerService.hasRoom(session) then
					hatch(egg, session, false)
				else
					setLabel(egg, eggTitle(egg), "Pen full! Sell a pet")
					if label then
						label.Text = "Pen full!"
					end
					if session and t - egg.warnedAt > 10 then
						egg.warnedAt = t
						PlayerService.notify(
							session.player,
							"Your pen is full! Sell a pet or buy more slots so your egg can hatch.",
							"warn"
						)
					end
				end
			else
				local seconds = math.ceil(egg.hatchAt - t)
				setLabel(egg, eggTitle(egg), `Hatching in {seconds}s`)
				local text = `{eggTitle(egg)} • {seconds}s`
				if label and label.Text ~= text then
					label.Text = text
				end
			end
		end
	end
	-- Dropped eggs expire back to where they came from.
	for _, egg in eggs do
		if egg.state == "dropped" then
			if t >= egg.dropExpires then
				returnToOrigin(egg)
			else
				setLabel(egg, eggTitle(egg), `Dropped! {math.ceil(egg.dropExpires - t)}s`)
			end
		end
	end
end

local function respawnTick()
	local t = now()
	for _, nest in nests do
		if nest.egg == nil and t >= nest.respawnAt then
			spawnInNest(nest, PetLogic.rollEggRarity(roll, EventState.factor("eggLuck")), false)
		end
	end
end

local function onCharacterLost(session: Session, _character: Model)
	local egg = carried[session.player]
	if egg then
		returnToOrigin(egg)
	end
end

local function onSessionEnding(session: Session)
	local player = session.player
	local egg = carried[player]
	if egg then
		returnToOrigin(egg)
	end
	-- Eggs still incubating at home finish instantly so nothing is lost by leaving.
	for _, slots in incubators do
		for _, incubating in slots do
			if incubating.baseOwner == player then
				if PlayerService.hasRoom(session) then
					hatch(incubating, session, true)
				else
					-- No room: pay out what the pet would sell for instead of losing the egg.
					local pet = PetLogic.petFor(incubating.biome, incubating.rarity)
					if pet then
						PlayerService.addCoins(session, pet.income * Config.Economy.sellSeconds)
					end
					destroyEgg(incubating)
				end
			end
		end
	end
	for _, other in eggs do
		if other.baseOwner == player then
			other.baseOwner = nil
		end
		if other.stolenFrom == player then
			other.stolenFrom = nil
		end
		if other.lastHolder == player then
			other.lastHolder = nil
		end
	end
end

-- Egg Shower: every empty nest refills right away.
function EggService.refillNests()
	local t = now()
	for _, nest in nests do
		if nest.egg == nil then
			nest.respawnAt = t
		end
	end
end

function EggService.start()
	local existing = workspace:FindFirstChild("Eggs")
	if existing then
		existing:Destroy()
	end
	eggsFolder = Instance.new("Folder")
	eggsFolder.Name = "Eggs"
	eggsFolder.Parent = workspace

	for _, plot in PlotService.getPlots() do
		incubators[plot] = {}
	end
	loadNests()

	PlotService.onShieldChanged(function(plot: Plot)
		for _, egg in incubators[plot] do
			updateStealPrompt(egg)
		end
	end)
	PlayerService.onCharacterLost(onCharacterLost)
	PlayerService.onSessionEnding(onSessionEnding)

	Loop.every("Respawn", 1, respawnTick, 0)
	Loop.every("Deposit", 0.1, depositTick)
	Loop.every("Hatch", 0.25, hatchTick)
	Loop.every("Jackpot", Config.Jackpot.interval, spawnJackpot, Config.Jackpot.firstDelay)
end

return EggService
