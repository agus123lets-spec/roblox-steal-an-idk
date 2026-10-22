--!strict
-- Rotating server events (Lucky Hour, Coin Rush, Egg Shower, ...) every few minutes.
-- Clients read workspace attributes EventKey / EventEndsAt for the HUD timer.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerService = require(script.Parent.PlayerService)
local EggService = require(script.Parent.EggService)
local EventState = require(script.Parent.EventState)
local Loop = require(script.Parent.Loop)

local EventService = {}

local random = Random.new()
local lastKey = ""

local function finish(info: Config.EventInfo)
	if EventState.active() ~= info then
		return
	end
	EventState.set(nil, 0)
	workspace:SetAttribute("EventKey", nil)
	workspace:SetAttribute("EventEndsAt", nil)
	PlayerService.recomputeAll()
	PlayerService.announce(`{info.icon} {info.name} is over!`, "info")
end

local function startEvent()
	local choices = {}
	for _, info in Config.Events.list do
		if info.key ~= lastKey then
			table.insert(choices, info)
		end
	end
	if #choices == 0 then
		return
	end
	local info = choices[random:NextInteger(1, #choices)]
	lastKey = info.key
	local finishAt = workspace:GetServerTimeNow() + info.duration
	EventState.set(info, finishAt)
	workspace:SetAttribute("EventKey", info.key)
	workspace:SetAttribute("EventEndsAt", finishAt)
	PlayerService.recomputeAll()
	if info.effects.respawn then
		EggService.refillNests()
	end
	PlayerService.announce(`{info.icon} {string.upper(info.name)}! {info.desc}`, "rare")
	task.delay(info.duration, finish, info)
end

function EventService.start()
	Loop.every("Events", Config.Events.interval, startEvent, Config.Events.firstDelay)
end

return EventService
