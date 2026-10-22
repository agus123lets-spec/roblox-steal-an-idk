--!strict
-- Rebirths (trade coins, Speed and shoes for permanent boosts) and pet fusion.

local HttpService: HttpService = game:GetService("HttpService")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PetLogic = require(ReplicatedStorage.Shared.PetLogic)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerService = require(script.Parent.PlayerService)
local EggService = require(script.Parent.EggService)
local RewardService = require(script.Parent.RewardService)
local Actions = require(script.Parent.Actions)

type Session = PlayerService.Session

local ProgressionService = {}

local function multiplierText(value: number): string
	local text = string.format("%.2f", value)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return "x" .. text
end

local function rebirth(session: Session, _arg: any): (boolean, string)
	local data = session.data
	local coinsNeeded, speedNeeded = Progression.rebirthRequirement(data.rebirths)
	if data.coins < coinsNeeded or data.speed < speedNeeded then
		return false, `Rebirth needs {Format.money(coinsNeeded)} and {Format.short(speedNeeded)} Speed.`
	end
	if EggService.isCarrying(session.player) then
		return false, "Bring your egg home before you rebirth!"
	end
	data.rebirths += 1
	data.coins = 0
	data.shoesLevel = 1
	PlayerService.setSpeed(session, 0)
	PlayerService.addFeathers(session, Config.Rebirth.feathers)
	PlayerService.recomputeIncome(session)
	PlayerService.announce(`♻️ {session.player.DisplayName} reached Rebirth {data.rebirths}!`, "rare")
	local root = PlayerService.rootOf(session.player)
	if root then
		Remotes.FX:FireAllClients("Rebirth", root.Position)
	end
	local income = multiplierText(Progression.rebirthIncomeMultiplier(data.rebirths))
	local training = multiplierText(Progression.rebirthTrainingMultiplier(data.rebirths))
	return true,
		`♻️ Rebirth {data.rebirths}! Income {income} and training {training} forever. +{Config.Rebirth.feathers} 🪶`
end

local function fuse(session: Session, kind: any): (boolean, string)
	local info = if type(kind) == "string" then Config.PetByKey[kind] else nil
	if not info then
		return false, "Pick a pet to fuse."
	end
	local selection = Progression.fuseSelection(session.data.pets, info.key)
	if not selection then
		return false, `You need {Config.Fusion.required} {info.name} to fuse.`
	end
	local resultKind, size, mutation = Progression.fuseResult(selection)
	if not resultKind then
		return false, `Your {info.name} can't get any bigger!`
	end
	local used: { [string]: boolean } = {}
	for _, pet in selection do
		used[pet.id] = true
	end
	local kept = {}
	for _, pet in session.data.pets do
		if not used[pet.id] then
			table.insert(kept, pet)
		end
	end
	session.data.pets = kept
	local newPet: PetLogic.PetData =
		{ id = HttpService:GenerateGUID(false), kind = resultKind, size = size, mutation = mutation }
	local isNew = not session.data.index[resultKind]
	PlayerService.addPet(session, newPet)
	RewardService.progress(session, "Fuse", 1)
	Remotes.Hatch:FireClient(session.player, {
		kind = resultKind,
		size = size,
		mutation = mutation,
		lucky = false,
		isNew = isNew,
		income = PetLogic.income(newPet),
		eggRarity = info.rarity,
		fused = true,
	})
	return true, `🧪 Fused 3 {info.name} into {PetLogic.describe(newPet)}!`
end

function ProgressionService.start()
	Actions.register("Rebirth", rebirth)
	Actions.register("Fuse", fuse)
end

return ProgressionService
