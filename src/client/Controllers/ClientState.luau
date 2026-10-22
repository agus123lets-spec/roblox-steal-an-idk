--!strict
-- Latest private state pushed by the server.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

export type PetData = { id: string, kind: string, size: string, mutation: string? }
export type Stats = { hatched: number, stolen: number, caught: number, laps: number, bestLap: number }
export type Quest = { id: string, target: number, progress: number, claimed: boolean, feathers: number }
export type State = {
	coins: number,
	speed: number,
	feathers: number,
	income: number,
	baseIncome: number,
	incomeMult: number,
	friendCount: number,
	rebirths: number,
	shoesLevel: number,
	slots: number,
	pets: { PetData },
	tools: { [string]: boolean },
	trails: { [string]: boolean },
	equippedTrail: string,
	themes: { [string]: boolean },
	equippedTheme: string,
	index: { [string]: boolean },
	stats: Stats,
	daily: { last: number, streak: number },
	quests: { day: number, list: { Quest }, bonusClaimed: boolean },
	codes: { [string]: boolean },
	luckUntil: number,
	turboUntil: number,
	persistent: boolean,
	walkSpeed: number,
}

local ClientState = {}

local current: State = {
	coins = 0,
	speed = 0,
	feathers = 0,
	income = 0,
	baseIncome = 0,
	incomeMult = 1,
	friendCount = 0,
	rebirths = 0,
	shoesLevel = 1,
	slots = 6,
	pets = {},
	tools = {},
	trails = {},
	equippedTrail = "",
	themes = {},
	equippedTheme = "",
	index = {},
	stats = { hatched = 0, stolen = 0, caught = 0, laps = 0, bestLap = 0 },
	daily = { last = 0, streak = 0 },
	quests = { day = -1, list = {}, bonusClaimed = false },
	codes = {},
	luckUntil = 0,
	turboUntil = 0,
	persistent = false,
	walkSpeed = 16,
}
local received = false
local listeners: { (State) -> () } = {}

function ClientState.get(): State
	return current
end

function ClientState.hasData(): boolean
	return received
end

function ClientState.onChanged(listener: (State) -> ())
	table.insert(listeners, listener)
end

function ClientState.start()
	Remotes.State.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		current = payload :: State
		received = true
		for _, listener in listeners do
			task.spawn(listener, current)
		end
	end)
end

return ClientState
