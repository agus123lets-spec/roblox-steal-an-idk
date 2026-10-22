--!strict
-- Routes Remotes.Action calls ("ClaimDaily", "Rebirth", "Fuse", ...) to the service that registered them.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerService = require(script.Parent.PlayerService)

type Handler = (PlayerService.Session, any) -> (boolean, string)

local Actions = {}

local handlers: { [string]: Handler } = {}

function Actions.register(name: string, handler: Handler)
	handlers[name] = handler
end

function Actions.start()
	Remotes.Action.OnServerInvoke = function(player: Player, name: any, arg: any): (boolean, string)
		local session = PlayerService.get(player)
		local handler = if type(name) == "string" then handlers[name] else nil
		if not session or not handler then
			return false, "Not ready yet."
		end
		local ok, success, message = pcall(handler, session, arg)
		session.dirty = true
		if not ok then
			warn(`[NestHeist] Action {name} failed for {player.Name}: {success}`)
			return false, "Something went wrong, try again."
		end
		return success, message
	end
end

return Actions
