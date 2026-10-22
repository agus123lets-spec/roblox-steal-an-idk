--!strict
-- Owns each player's live session: money, Speed, pets, timed effects, walk speed, friend boosts,
-- leaderstats, the follower pet and syncing state to the client.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PetLogic = require(ReplicatedStorage.Shared.PetLogic)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local EventState = require(script.Parent.EventState)
local Loop = require(script.Parent.Loop)

export type Session = {
	player: Player,
	data: DataService.SaveData,
	persistent: boolean,
	baseIncome: number,
	income: number,
	friendCount: number,
	stunUntil: number,
	slowUntil: number,
	slowFactor: number,
	luckUntil: number,
	turboUntil: number,
	revengeTargetId: number,
	revengeUntil: number,
	speedRemainder: number,
	dirty: boolean,
	ended: boolean,
	rebirthsValue: IntValue,
	speedValue: StringValue,
	coinsValue: StringValue,
}

type SessionCallback = (Session) -> ()
type CharacterCallback = (Session, Model) -> ()

local PlayerService = {}

local sessions: { [Player]: Session } = {}
local startedCallbacks: { SessionCallback } = {}
local endingCallbacks: { SessionCallback } = {}
local petsChangedCallbacks: { SessionCallback } = {}
local spawnedCallbacks: { CharacterCallback } = {}
local diedCallbacks: { CharacterCallback } = {}

function PlayerService.onSessionStarted(callback: SessionCallback)
	table.insert(startedCallbacks, callback)
end
-- Ending callbacks run synchronously, newest first, before the final save.
function PlayerService.onSessionEnding(callback: SessionCallback)
	table.insert(endingCallbacks, 1, callback)
end
function PlayerService.onPetsChanged(callback: SessionCallback)
	table.insert(petsChangedCallbacks, callback)
end
function PlayerService.onCharacterSpawned(callback: CharacterCallback)
	table.insert(spawnedCallbacks, callback)
end
-- Fires on death and when the character is removed (respawn/leave).
function PlayerService.onCharacterLost(callback: CharacterCallback)
	table.insert(diedCallbacks, callback)
end

function PlayerService.now(): number
	return workspace:GetServerTimeNow()
end

function PlayerService.get(player: Player): Session?
	local session = sessions[player]
	if session and not session.ended then
		return session
	end
	return nil
end

function PlayerService.all(): { Session }
	local list = {}
	for _, session in sessions do
		if not session.ended then
			table.insert(list, session)
		end
	end
	return list
end

function PlayerService.rootOf(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function PlayerService.notify(player: Player, text: string, kind: string?)
	if player.Parent then
		Remotes.Notify:FireClient(player, text, kind or "info")
	end
end

function PlayerService.announce(text: string, kind: string?)
	Remotes.Announce:FireAllClients(text, kind or "info")
end

---------------------------------------------------------------------------
-- Income
---------------------------------------------------------------------------
function PlayerService.incomeMultiplier(session: Session): number
	local data = session.data
	return Progression.incomeMultiplier(data.rebirths, data.index, session.friendCount) * EventState.factor("income")
end

function PlayerService.recomputeIncome(session: Session)
	session.baseIncome = PetLogic.totalIncome(session.data.pets)
	session.income = session.baseIncome * PlayerService.incomeMultiplier(session)
	session.dirty = true
end

-- After a server event starts or ends.
function PlayerService.recomputeAll()
	for _, session in sessions do
		if not session.ended then
			PlayerService.recomputeIncome(session)
		end
	end
end

---------------------------------------------------------------------------
-- Stats
---------------------------------------------------------------------------
function PlayerService.addCoins(session: Session, amount: number)
	session.data.coins += amount
	session.dirty = true
end

function PlayerService.trySpend(session: Session, amount: number): boolean
	if session.data.coins + 1e-6 < amount then
		return false
	end
	session.data.coins = math.max(0, session.data.coins - amount)
	session.dirty = true
	return true
end

function PlayerService.addSpeed(session: Session, amount: number)
	session.data.speed += math.floor(amount)
	session.player:SetAttribute("Speed", session.data.speed)
	session.dirty = true
end

function PlayerService.setSpeed(session: Session, value: number)
	session.data.speed = math.max(0, math.floor(value))
	session.speedRemainder = 0
	session.player:SetAttribute("Speed", session.data.speed)
	session.dirty = true
end

function PlayerService.addFeathers(session: Session, amount: number)
	session.data.feathers += math.floor(amount)
	session.dirty = true
end

function PlayerService.trySpendFeathers(session: Session, amount: number): boolean
	if session.data.feathers < amount then
		return false
	end
	session.data.feathers -= amount
	session.dirty = true
	return true
end

function PlayerService.hasRoom(session: Session): boolean
	return #session.data.pets < session.data.slots
end

-- Every client renders each player's best pet following them, from this attribute.
local function updateFollower(session: Session)
	local best: PetLogic.PetData? = nil
	local bestIncome = -1
	for _, pet in session.data.pets do
		local income = PetLogic.income(pet)
		if income > bestIncome then
			best = pet
			bestIncome = income
		end
	end
	local value = if best then `{best.kind}|{best.size}|{best.mutation or ""}` else ""
	if session.player:GetAttribute("Follower") ~= value then
		session.player:SetAttribute("Follower", value)
	end
end

function PlayerService.petsChanged(session: Session)
	PlayerService.recomputeIncome(session)
	updateFollower(session)
	for _, callback in petsChangedCallbacks do
		task.spawn(callback, session)
	end
end

function PlayerService.addPet(session: Session, pet: PetLogic.PetData): boolean
	if not PlayerService.hasRoom(session) then
		return false
	end
	table.insert(session.data.pets, pet)
	local newKind = not session.data.index[pet.kind]
	session.data.index[pet.kind] = true
	PlayerService.petsChanged(session)
	if newKind then
		local info = Config.PetByKey[pet.kind]
		local biome = if info then Config.BiomeByKey[info.biome] else nil
		if biome and Progression.biomeComplete(session.data.index, biome.key) then
			local bonus = math.floor(Config.Index.biomeBonus * 100 + 0.5)
			PlayerService.notify(
				session.player,
				`📖 {biome.icon} {biome.name} Index complete! +{bonus}% income forever!`,
				"rare"
			)
			PlayerService.announce(`📖 {session.player.DisplayName} completed the {biome.name} Index!`, "rare")
		end
	end
	return true
end

function PlayerService.removePet(session: Session, petId: string): PetLogic.PetData?
	for index, pet in session.data.pets do
		if pet.id == petId then
			table.remove(session.data.pets, index)
			PlayerService.petsChanged(session)
			return pet
		end
	end
	return nil
end

function PlayerService.luckOf(session: Session): number
	local luck = if PlayerService.now() < session.luckUntil then 2 else 1
	return luck * EventState.factor("luck")
end

function PlayerService.trainingMultiplier(session: Session): number
	local shoes = Config.Shoes[session.data.shoesLevel]
	local mult = (if shoes then shoes.mult else 1) * Progression.rebirthTrainingMultiplier(session.data.rebirths)
	if PlayerService.now() < session.turboUntil then
		mult *= 2
	end
	return mult * EventState.factor("training")
end

---------------------------------------------------------------------------
-- Movement effects
---------------------------------------------------------------------------
local function applyMovement(session: Session)
	local character = session.player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local now = PlayerService.now()
	local walkSpeed = PetLogic.walkSpeedFor(session.data.speed)
	local jumpHeight = Config.Movement.jumpHeight
	if now < session.stunUntil then
		walkSpeed = 0
		jumpHeight = 0
	elseif now < session.slowUntil then
		walkSpeed *= session.slowFactor
	end
	if math.abs(humanoid.WalkSpeed - walkSpeed) > 0.01 then
		humanoid.WalkSpeed = walkSpeed
	end
	-- JumpHeight is stored as a float32, so compare with a tolerance.
	if math.abs(humanoid.JumpHeight - jumpHeight) > 0.01 then
		humanoid.JumpHeight = jumpHeight
	end
end

function PlayerService.stun(session: Session, duration: number, knockDirection: Vector3?)
	session.stunUntil = math.max(session.stunUntil, PlayerService.now() + duration)
	applyMovement(session)
	if session.player.Parent then
		Remotes.Knockback:FireClient(session.player, knockDirection or Vector3.zero, duration)
	end
end

function PlayerService.slow(session: Session, factor: number, duration: number)
	session.slowFactor = factor
	session.slowUntil = math.max(session.slowUntil, PlayerService.now() + duration)
	applyMovement(session)
end

function PlayerService.isStunned(session: Session): boolean
	return PlayerService.now() < session.stunUntil
end

---------------------------------------------------------------------------
-- Revenge & fair play
---------------------------------------------------------------------------
function PlayerService.setRevenge(victim: Session, thief: Player)
	victim.revengeTargetId = thief.UserId
	victim.revengeUntil = PlayerService.now() + Config.Steal.revengeDuration
	if victim.player.Parent then
		Remotes.Revenge:FireClient(victim.player, thief, victim.revengeUntil)
	end
end

function PlayerService.isRevengeTarget(hunter: Session, target: Player): boolean
	return hunter.revengeTargetId == target.UserId and PlayerService.now() < hunter.revengeUntil
end

-- Called when the victim already got their egg back, so the "hunt the thief" UI goes away.
function PlayerService.clearRevenge(session: Session)
	if session.revengeUntil == 0 then
		return
	end
	session.revengeTargetId = 0
	session.revengeUntil = 0
	if session.player.Parent then
		Remotes.Revenge:FireClient(session.player, nil, 0)
	end
end

-- Can `attacker` net or rob `target`? Revenge always allowed; otherwise the fair-play rule.
function PlayerService.canTarget(attacker: Session, target: Session): (boolean, string?)
	if PlayerService.isRevengeTarget(attacker, target.player) then
		return true, nil
	end
	if not PetLogic.canSteal(attacker.data.speed, target.data.speed) then
		return false, `{target.player.DisplayName} is way slower than you. Pick on someone your own size!`
	end
	return true, nil
end

---------------------------------------------------------------------------
-- Friends boost
---------------------------------------------------------------------------
local friendCache: { [string]: boolean } = {}
local friendsRefreshQueued = false

local function areFriends(a: Player, b: Player): boolean
	local key = if a.UserId < b.UserId then `{a.UserId}:{b.UserId}` else `{b.UserId}:{a.UserId}`
	local cached = friendCache[key]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function()
		return a:IsFriendsWithAsync(b.UserId)
	end)
	local friends = ok and result == true
	if ok then
		friendCache[key] = friends
	end
	return friends
end

-- Batched a moment after joins/leaves; IsFriendsWith is a web call, so it runs off a snapshot.
local function refreshFriends()
	if friendsRefreshQueued then
		return
	end
	friendsRefreshQueued = true
	task.delay(2, function()
		friendsRefreshQueued = false
		local list = PlayerService.all()
		for _, session in list do
			local count = 0
			for _, other in list do
				if other ~= session and not other.ended and areFriends(session.player, other.player) then
					count += 1
				end
			end
			if not session.ended and count ~= session.friendCount then
				local gained = count > session.friendCount
				session.friendCount = count
				PlayerService.recomputeIncome(session)
				if gained then
					local bonus = math.floor((Progression.friendMultiplier(count) - 1) * 100 + 0.5)
					PlayerService.notify(session.player, `👥 Playing with friends: +{bonus}% income!`, "success")
				end
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Sync
---------------------------------------------------------------------------
local function buildState(session: Session): { [string]: any }
	local data = session.data
	return {
		coins = data.coins,
		speed = data.speed,
		feathers = data.feathers,
		income = session.income,
		baseIncome = session.baseIncome,
		incomeMult = PlayerService.incomeMultiplier(session),
		friendCount = session.friendCount,
		rebirths = data.rebirths,
		shoesLevel = data.shoesLevel,
		slots = data.slots,
		pets = data.pets,
		tools = data.tools,
		trails = data.trails,
		equippedTrail = data.equippedTrail,
		themes = data.themes,
		equippedTheme = data.equippedTheme,
		index = data.index,
		stats = data.stats,
		daily = data.daily,
		quests = data.quests,
		codes = data.codes,
		luckUntil = session.luckUntil,
		turboUntil = session.turboUntil,
		persistent = session.persistent,
		walkSpeed = PetLogic.walkSpeedFor(data.speed),
	}
end

local function updateLeaderstats(session: Session)
	if session.rebirthsValue.Value ~= session.data.rebirths then
		session.rebirthsValue.Value = session.data.rebirths
	end
	-- Formatted strings: coin counts outgrow what an IntValue can hold.
	local speed = Format.short(session.data.speed)
	if session.speedValue.Value ~= speed then
		session.speedValue.Value = speed
	end
	local coins = Format.money(session.data.coins)
	if session.coinsValue.Value ~= coins then
		session.coinsValue.Value = coins
	end
end

---------------------------------------------------------------------------
-- Session lifecycle
---------------------------------------------------------------------------
local function onCharacter(session: Session, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or session.ended then
		return
	end
	applyMovement(session)
	humanoid.Died:Connect(function()
		for _, callback in diedCallbacks do
			task.spawn(callback, session, character)
		end
	end)
	for _, callback in spawnedCallbacks do
		task.spawn(callback, session, character)
	end
end

local function welcome(session: Session, offlineEarned: number)
	local player = session.player
	if not session.persistent then
		if RunService:IsStudio() then
			PlayerService.notify(
				player,
				"Saving is off in this test. Publish the game and enable Studio API access to save progress.",
				"warn"
			)
		else
			PlayerService.notify(
				player,
				"We couldn't load your saved progress, so this session won't save. Please rejoin in a minute.",
				"danger"
			)
		end
	end
	if offlineEarned > 0 then
		PlayerService.notify(
			player,
			`Welcome back! Your pets earned {Format.money(offlineEarned)} while you were away.`,
			"success"
		)
	end
	if session.data.stats.hatched == 0 and #session.data.pets == 0 then
		task.delay(2, function()
			PlayerService.notify(
				player,
				"Welcome to Nest Heist! Follow the glowing trail to 🌼 Meadow Hollow and hold E on an egg.",
				"info"
			)
		end)
		task.delay(9, function()
			PlayerService.notify(player, "Carry it home to your nest before the guardian catches you!", "info")
		end)
	end
end

local function startSession(player: Player)
	local data, persistent = DataService.load(player)
	if not player.Parent then
		if persistent then
			DataService.save(player, data, true)
		end
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local rebirthsValue = Instance.new("IntValue")
	rebirthsValue.Name = "Rebirths"
	rebirthsValue.Parent = leaderstats
	local speedValue = Instance.new("StringValue")
	speedValue.Name = "Speed"
	speedValue.Parent = leaderstats
	local coinsValue = Instance.new("StringValue")
	coinsValue.Name = "Coins"
	coinsValue.Parent = leaderstats
	leaderstats.Parent = player

	local session: Session = {
		player = player,
		data = data,
		persistent = persistent,
		baseIncome = 0,
		income = 0,
		friendCount = 0,
		stunUntil = 0,
		slowUntil = 0,
		slowFactor = 1,
		luckUntil = 0,
		turboUntil = 0,
		revengeTargetId = 0,
		revengeUntil = 0,
		speedRemainder = 0,
		dirty = true,
		ended = false,
		rebirthsValue = rebirthsValue,
		speedValue = speedValue,
		coinsValue = coinsValue,
	}
	sessions[player] = session
	PlayerService.recomputeIncome(session)

	local offlineEarned = 0
	if data.lastOnline > 0 then
		-- Offline pets earn with your permanent boosts, but not friends or events.
		local offlineIncome = session.baseIncome * Progression.incomeMultiplier(data.rebirths, data.index, 0)
		offlineEarned = PetLogic.offlineEarnings(offlineIncome, os.time() - data.lastOnline)
		if offlineEarned > 0 then
			PlayerService.addCoins(session, offlineEarned)
		end
	end

	player:SetAttribute("Speed", data.speed)
	updateFollower(session)
	updateLeaderstats(session)

	for _, callback in startedCallbacks do
		task.spawn(callback, session)
	end

	player.CharacterAdded:Connect(function(character)
		onCharacter(session, character)
	end)
	player.CharacterRemoving:Connect(function(character)
		for _, callback in diedCallbacks do
			task.spawn(callback, session, character)
		end
	end)
	if player.Character then
		task.spawn(onCharacter, session, player.Character)
	end

	welcome(session, offlineEarned)
	refreshFriends()
end

local function endSession(player: Player)
	local session = sessions[player]
	if not session or session.ended then
		return
	end
	for _, callback in endingCallbacks do
		local ok, err = pcall(function(): string?
			callback(session)
			return nil
		end)
		if not ok then
			warn("[NestHeist] Session cleanup error:", err)
		end
	end
	session.ended = true
	sessions[player] = nil
	refreshFriends()
	if session.persistent then
		DataService.save(player, session.data, true)
	end
end

function PlayerService.start()
	Players.PlayerAdded:Connect(startSession)
	Players.PlayerRemoving:Connect(endSession)
	for _, player in Players:GetPlayers() do
		task.spawn(startSession, player)
	end

	-- Passive income.
	Loop.every("Income", 1, function()
		for _, session in sessions do
			if not session.ended then
				if session.income > 0 then
					PlayerService.addCoins(session, session.income)
				end
				updateLeaderstats(session)
			end
		end
	end)

	-- Walk speed effects and client sync.
	Loop.every("Sync", 0.2, function()
		for _, session in sessions do
			if not session.ended then
				applyMovement(session)
				if session.dirty then
					session.dirty = false
					Remotes.State:FireClient(session.player, buildState(session))
				end
			end
		end
	end)

	-- Autosave.
	Loop.every("Autosave", Config.Data.autosaveInterval, function()
		for player, session in sessions do
			if session.persistent and not session.ended then
				task.spawn(DataService.save, player, session.data, false)
			end
		end
	end)

	-- On shutdown, save everyone still here and wait for every in-flight save
	-- (including ones started by PlayerRemoving) before the server closes.
	game:BindToClose(function()
		for player, session in sessions do
			if session.persistent and not session.ended then
				task.spawn(DataService.save, player, session.data, true)
			end
		end
		local deadline = os.clock() + 25
		while DataService.inflight() > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return PlayerService
