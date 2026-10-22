--!strict
-- RemoteEvents/RemoteFunctions, created by the server on first require and awaited by clients.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

local EVENTS = {
	"State", -- server -> client: full private state snapshot
	"Notify", -- server -> client: toast (text, kind)
	"Announce", -- server -> all: big banner (text, kind)
	"Hatch", -- server -> client: hatch reveal data
	"Carry", -- server -> client: "start" | "end"
	"Guardian", -- server -> client: "chase" | "escaped" | "caught"
	"Knockback", -- server -> client: (direction, duration)
	"Revenge", -- server -> client: (thief Player?, endsAt)
	"Lap", -- server -> client: training lap events
	"Floater", -- server -> client: small "+N" popups
	"FX", -- server -> all: cosmetic effects
	"UseTool", -- client -> server: (toolKey, aimPosition)
}
local FUNCTIONS = {
	"Purchase", -- client -> server: (itemId) -> (ok, message)
	"SellPet", -- client -> server: (petId) -> (ok, message)
	"Action", -- client -> server: (action, arg) -> (ok, message): rewards, rebirth, fusion, codes
}

local isServer = RunService:IsServer()
local folder: Instance

if isServer then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		folder = existing
	else
		local created = Instance.new("Folder")
		created.Name = "Remotes"
		created.Parent = ReplicatedStorage
		folder = created
	end
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in FUNCTIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

local function event(name: string): RemoteEvent
	local instance = if isServer then folder:FindFirstChild(name) else folder:WaitForChild(name)
	if instance and instance:IsA("RemoteEvent") then
		return instance
	end
	error("Missing RemoteEvent " .. name)
end

local function func(name: string): RemoteFunction
	local instance = if isServer then folder:FindFirstChild(name) else folder:WaitForChild(name)
	if instance and instance:IsA("RemoteFunction") then
		return instance
	end
	error("Missing RemoteFunction " .. name)
end

return {
	State = event("State"),
	Notify = event("Notify"),
	Announce = event("Announce"),
	Hatch = event("Hatch"),
	Carry = event("Carry"),
	Guardian = event("Guardian"),
	Knockback = event("Knockback"),
	Revenge = event("Revenge"),
	Lap = event("Lap"),
	Floater = event("Floater"),
	FX = event("FX"),
	UseTool = event("UseTool"),
	Purchase = func("Purchase"),
	SellPet = func("SellPet"),
	Action = func("Action"),
}
