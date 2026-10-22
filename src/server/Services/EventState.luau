--!strict
-- The current server-wide event. Plain state, so any service can read it without require cycles;
-- EventService decides when events start and stop.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local EventState = {}

local current: Config.EventInfo? = nil
local endsAt = 0

function EventState.set(info: Config.EventInfo?, finishAt: number)
	current = info
	endsAt = finishAt
end

function EventState.active(): Config.EventInfo?
	if current and workspace:GetServerTimeNow() < endsAt then
		return current
	end
	return nil
end

-- Multiplier for one effect (luck, income, training, eggLuck, respawn, guardianSpeed); 1 when idle.
function EventState.factor(effect: string): number
	local info = EventState.active()
	if info then
		return info.effects[effect] or 1
	end
	return 1
end

return EventState
