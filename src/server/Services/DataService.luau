--!strict
-- Loads and saves player progress with a simple session lock so two servers never
-- overwrite each other. Falls back to an unsaved session when DataStores are unavailable
-- (e.g. an unpublished place in Studio).

local DataStoreService: DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PetLogic = require(ReplicatedStorage.Shared.PetLogic)
local Progression = require(ReplicatedStorage.Shared.Progression)

export type Stats = { hatched: number, stolen: number, caught: number, laps: number, bestLap: number }
export type SaveData = {
	version: number,
	coins: number,
	speed: number,
	feathers: number,
	shoesLevel: number,
	slots: number,
	pets: { PetLogic.PetData },
	tools: { [string]: boolean },
	trails: { [string]: boolean },
	equippedTrail: string,
	index: { [string]: boolean },
	stats: Stats,
	lastOnline: number,
	rebirths: number,
	themes: { [string]: boolean },
	equippedTheme: string,
	codes: { [string]: boolean },
	daily: { last: number, streak: number },
	quests: { day: number, list: { Progression.Quest }, bonusClaimed: boolean },
}

local DataService = {}

local DATA_VERSION = 1
local LOCK_TIMEOUT = 300

local store: DataStore? = nil
local storeError: string? = nil
local inflightSaves = 0

local function getStore(): DataStore?
	if store or storeError then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.storeName)
	end)
	if ok then
		store = result
	else
		storeError = tostring(result)
	end
	return store
end

local function num(value: any, fallback: number): number
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return fallback
end

local function boolMap(value: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(value) == "table" then
		for key, flag in value do
			if type(key) == "string" and flag == true then
				out[key] = true
			end
		end
	end
	return out
end

function DataService.defaultData(): SaveData
	return {
		version = DATA_VERSION,
		coins = 0,
		speed = 0,
		feathers = 0,
		shoesLevel = 1,
		slots = Config.Plots.startSlots,
		pets = {},
		tools = {},
		trails = {},
		equippedTrail = "",
		index = {},
		stats = { hatched = 0, stolen = 0, caught = 0, laps = 0, bestLap = 0 },
		lastOnline = 0,
		rebirths = 0,
		themes = {},
		equippedTheme = "",
		codes = {},
		daily = { last = 0, streak = 0 },
		quests = { day = -1, list = {}, bonusClaimed = false },
	}
end

-- Turns whatever was stored into valid SaveData, dropping anything unknown or corrupt.
function DataService.reconcile(raw: any): SaveData
	local data = DataService.defaultData()
	if type(raw) ~= "table" then
		return data
	end
	data.coins = math.max(0, num(raw.coins, 0))
	data.speed = math.max(0, math.floor(num(raw.speed, 0)))
	data.feathers = math.max(0, math.floor(num(raw.feathers, 0)))
	data.shoesLevel = math.clamp(math.floor(num(raw.shoesLevel, 1)), 1, #Config.Shoes)
	data.slots =
		math.clamp(math.floor(num(raw.slots, Config.Plots.startSlots)), Config.Plots.startSlots, Config.Plots.maxSlots)
	if type(raw.pets) == "table" then
		for _, pet in raw.pets do
			if
				type(pet) == "table"
				and type(pet.id) == "string"
				and type(pet.kind) == "string"
				and Config.PetByKey[pet.kind] ~= nil
				and type(pet.size) == "string"
				and PetLogic.sizeInfo(pet.size) ~= nil
			then
				local mutation: string? = nil
				if type(pet.mutation) == "string" and PetLogic.mutationInfo(pet.mutation) then
					mutation = pet.mutation
				end
				table.insert(data.pets, { id = pet.id, kind = pet.kind, size = pet.size, mutation = mutation })
			end
		end
	end
	data.tools = boolMap(raw.tools)
	data.trails = boolMap(raw.trails)
	if type(raw.equippedTrail) == "string" and data.trails[raw.equippedTrail] then
		data.equippedTrail = raw.equippedTrail
	end
	data.index = boolMap(raw.index)
	if type(raw.stats) == "table" then
		data.stats.hatched = math.max(0, math.floor(num(raw.stats.hatched, 0)))
		data.stats.stolen = math.max(0, math.floor(num(raw.stats.stolen, 0)))
		data.stats.caught = math.max(0, math.floor(num(raw.stats.caught, 0)))
		data.stats.laps = math.max(0, math.floor(num(raw.stats.laps, 0)))
		data.stats.bestLap = math.max(0, num(raw.stats.bestLap, 0))
	end
	data.lastOnline = num(raw.lastOnline, 0)
	data.rebirths = math.max(0, math.floor(num(raw.rebirths, 0)))
	data.themes = boolMap(raw.themes)
	if type(raw.equippedTheme) == "string" and data.themes[raw.equippedTheme] then
		data.equippedTheme = raw.equippedTheme
	end
	data.codes = boolMap(raw.codes)
	if type(raw.daily) == "table" then
		data.daily.last = math.max(0, num(raw.daily.last, 0))
		data.daily.streak = math.max(0, math.floor(num(raw.daily.streak, 0)))
	end
	if type(raw.quests) == "table" and type(raw.quests.list) == "table" then
		local list: { Progression.Quest } = {}
		for _, quest in raw.quests.list do
			if type(quest) == "table" and type(quest.id) == "string" and Progression.questInfo(quest.id) then
				table.insert(list, {
					id = quest.id,
					target = math.max(1, math.floor(num(quest.target, 1))),
					progress = math.max(0, math.floor(num(quest.progress, 0))),
					claimed = quest.claimed == true,
					feathers = math.max(0, math.floor(num(quest.feathers, 0))),
				})
			end
		end
		data.quests = {
			day = math.floor(num(raw.quests.day, -1)),
			list = list,
			bonusClaimed = raw.quests.bonusClaimed == true,
		}
	end
	return data
end

local function keyFor(player: Player): string
	return "u_" .. player.UserId
end

-- Returns the player's data and whether it will be saved.
function DataService.load(player: Player): (SaveData, boolean)
	local ds = getStore()
	if not ds then
		warn("[NestHeist] DataStores unavailable, progress will not be saved:", storeError)
		return DataService.defaultData(), false
	end
	local isStudio = RunService:IsStudio()
	local maxAttempts = if isStudio then 1 else 6
	for attempt = 1, maxAttempts do
		local locked = false
		local loaded: any = nil
		local ok, err = pcall(function()
			ds:UpdateAsync(keyFor(player), function(old: any): any
				locked = false
				loaded = nil
				if type(old) == "table" and type(old.lock) == "table" then
					local lockedByOther = old.lock.job ~= game.JobId and os.time() - num(old.lock.t, 0) < LOCK_TIMEOUT
					-- Studio never takes over a live server's lock; live servers do on the last attempt.
					if lockedByOther and (attempt < maxAttempts or isStudio) then
						locked = true
						loaded = old.data
						return nil
					end
				end
				local wrapper = if type(old) == "table" then old else {}
				loaded = wrapper.data
				wrapper.lock = { job = game.JobId, t = os.time() }
				return wrapper
			end)
		end)
		if ok and not locked then
			return DataService.reconcile(loaded), true
		end
		if ok and locked and isStudio then
			warn(`[NestHeist] {player.Name}'s profile is open on a live server; this Studio session will not save.`)
			return DataService.reconcile(loaded), false
		end
		if not ok then
			warn(`[NestHeist] Load attempt {attempt} failed for {player.Name}: {err}`)
		end
		if attempt < maxAttempts then
			task.wait(if locked then 3 else 2 * attempt)
			if not player.Parent then
				break
			end
		end
	end
	return DataService.defaultData(), false
end

-- Number of saves currently talking to the DataStore (BindToClose waits for these).
function DataService.inflight(): number
	return inflightSaves
end

function DataService.save(player: Player, data: SaveData, release: boolean): boolean
	local ds = getStore()
	if not ds then
		return false
	end
	data.lastOnline = os.time()
	inflightSaves += 1
	local cancelled = false
	local ok, err = pcall(function()
		ds:UpdateAsync(keyFor(player), function(old: any): any
			cancelled = false
			if type(old) == "table" and type(old.lock) == "table" and old.lock.job ~= game.JobId then
				cancelled = true
				return nil -- another server took over this profile; don't clobber it
			end
			return {
				data = data,
				lock = if release then nil else { job = game.JobId, t = os.time() },
			}
		end)
	end)
	inflightSaves -= 1
	if not ok then
		warn(`[NestHeist] Save failed for {player.Name}: {err}`)
	elseif cancelled then
		warn(`[NestHeist] Skipped saving {player.Name}: another server owns this profile`)
	end
	return ok and not cancelled
end

return DataService
