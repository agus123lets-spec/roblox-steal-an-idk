--!strict
-- Owns each player's live session: money, Speed, pets, timed effects, walk speed,
-- leaderstats and syncing state to the client.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PetLogic = require(ReplicatedStorage.Shared.PetLogic)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)

export type Session = {
	player: Player,
	data: DataService.SaveData,
	persistent: boolean,
	income: number,
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
	coinsValue: IntValue,
	speedValue: IntValue,
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
-- Stats
---------------------------------------------------------------------------
function PlayerService.recomputeIncome(session: Session)
	session.income = PetLogic.totalIncome(session.data.pets)
	session.dirty = true
end

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

function PlayerService.petsChanged(session: Session)
	PlayerService.recomputeIncome(session)
	for _, callback in petsChangedCallbacks do
		task.spawn(callback, session)
	end
end

function PlayerService.addPet(session: Session, pet: PetLogic.PetData): boolean
	if not PlayerService.hasRoom(session) then
		return false
	end
	table.insert(session.data.pets, pet)
	session.data.index[pet.kind] = true
	PlayerService.petsChanged(session)
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
	return if PlayerService.now() < session.luckUntil then 2 else 1
end

function PlayerService.trainingMultiplier(session: Session): number
	local shoes = Config.Shoes[session.data.shoesLevel]
	local mult = if shoes then shoes.mult else 1
	if PlayerService.now() < session.turboUntil then
		mult *= 2
	end
	return mult
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
	if humanoid.JumpHeight ~= jumpHeight then
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
-- Sync
---------------------------------------------------------------------------
local function buildState(session: Session): { [string]: any }
	local data = session.data
	return {
		coins = data.coins,
		speed = data.speed,
		feathers = data.feathers,
		income = session.income,
		shoesLevel = data.shoesLevel,
		slots = data.slots,
		pets = data.pets,
		tools = data.tools,
		trails = data.trails,
		equippedTrail = data.equippedTrail,
		index = data.index,
		stats = data.stats,
		luckUntil = session.luckUntil,
		turboUntil = session.turboUntil,
		persistent = session.persistent,
		walkSpeed = PetLogic.walkSpeedFor(data.speed),
	}
end

local function updateLeaderstats(session: Session)
	session.coinsValue.Value = math.floor(session.data.coins)
	session.speedValue.Value = session.data.speed
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
		PlayerService.notify(
			player,
			"Saving is off in this test. Publish the game and enable Studio API access to save progress.",
			"warn"
		)
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
				"Welcome to Nest Heist! Cross the bridge to 🌼 Meadow Hollow and hold E on an egg.",
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
	local coinsValue = Instance.new("IntValue")
	coinsValue.Name = "Coins"
	coinsValue.Parent = leaderstats
	local speedValue = Instance.new("IntValue")
	speedValue.Name = "Speed"
	speedValue.Parent = leaderstats
	leaderstats.Parent = player

	local session: Session = {
		player = player,
		data = data,
		persistent = persistent,
		income = 0,
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
		coinsValue = coinsValue,
		speedValue = speedValue,
	}
	sessions[player] = session
	PlayerService.recomputeIncome(session)

	local offlineEarned = 0
	if data.lastOnline > 0 then
		offlineEarned = PetLogic.offlineEarnings(session.income, os.time() - data.lastOnline)
		if offlineEarned > 0 then
			PlayerService.addCoins(session, offlineEarned)
		end
	end

	player:SetAttribute("Speed", data.speed)
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
	task.spawn(function()
		while true do
			task.wait(1)
			for _, session in sessions do
				if not session.ended then
					if session.income > 0 then
						PlayerService.addCoins(session, session.income)
					end
					updateLeaderstats(session)
				end
			end
		end
	end)

	-- Walk speed effects and client sync.
	task.spawn(function()
		while true do
			task.wait(0.2)
			for _, session in sessions do
				if not session.ended then
					applyMovement(session)
					if session.dirty then
						session.dirty = false
						Remotes.State:FireClient(session.player, buildState(session))
					end
				end
			end
		end
	end)

	-- Autosave.
	task.spawn(function()
		while true do
			task.wait(Config.Data.autosaveInterval)
			for player, session in sessions do
				if session.persistent and not session.ended then
					task.spawn(DataService.save, player, session.data, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player, session in sessions do
			if session.persistent and not session.ended then
				pending += 1
				task.spawn(function()
					DataService.save(player, session.data, true)
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return PlayerService
