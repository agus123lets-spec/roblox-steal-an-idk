--!strict
-- Every player's best pet follows them around. Rendered locally on each client from the
-- player's "Follower" attribute, so it costs the server nothing.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PetLogic = require(ReplicatedStorage.Shared.PetLogic)
local Builders = require(ReplicatedStorage.Shared.Builders)

type Follower = { key: string, model: Model?, position: Vector3?, look: Vector3, phase: number }

local Followers = {}

-- Parked far above the map while hidden (at -500 and below the engine deletes parts).
local HIDDEN = CFrame.new(0, 4000, 0)

local folder: Folder
local followers: { [Player]: Follower } = {}

local function parse(value: any): (string?, string, string?)
	if type(value) ~= "string" then
		return nil, "Normal", nil
	end
	local kind, size, mutation = string.match(value, "^([^|]*)|([^|]*)|([^|]*)$")
	if not kind or not Config.PetByKey[kind] then
		return nil, "Normal", nil
	end
	return kind, if size and size ~= "" then size else "Normal", if mutation and mutation ~= "" then mutation else nil
end

local function rebuild(player: Player)
	local value = player:GetAttribute("Follower")
	local key = if type(value) == "string" then value else ""
	local entry = followers[player]
	if entry and entry.key == key then
		return
	end
	if entry and entry.model then
		entry.model:Destroy()
	end
	local kind, size, mutation = parse(value)
	local model: Model? = nil
	if kind then
		local sizeInfo = PetLogic.sizeInfo(size)
		-- Big pets still shrink a little so they don't block the view.
		local scale = Config.Follower.scale * (if sizeInfo then math.min(sizeInfo.scale, 1.4) else 1)
		local built = Builders.pet(kind, scale, mutation, HIDDEN)
		built.Name = player.Name .. "Follower"
		built.Parent = folder
		model = built
	end
	followers[player] =
		{ key = key, model = model, position = nil, look = Vector3.new(0, 0, -1), phase = math.random() * 6 }
end

local function groundOffset(character: Model, root: BasePart): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return 3
end

local function update(dt: number)
	local t = os.clock()
	for player, entry in followers do
		local model = entry.model
		if model then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if character and root and root:IsA("BasePart") then
				local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
				look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
				local right = Vector3.new(-look.Z, 0, look.X)
				local target = root.Position
					- look * Config.Follower.back
					+ right * Config.Follower.side
					- Vector3.new(0, groundOffset(character, root), 0)
				local current = entry.position
				if not current or (current - target).Magnitude > 60 then
					current = target
				end
				local nextPosition = (current :: Vector3):Lerp(target, 1 - math.exp(-dt * 8))
				local moved = nextPosition - (current :: Vector3)
				local flatMove = Vector3.new(moved.X, 0, moved.Z)
				local moving = flatMove.Magnitude > 0.02
				if moving then
					entry.look = flatMove.Unit
				end
				entry.position = nextPosition
				local bob = if moving
					then math.abs(math.sin(t * 10 + entry.phase)) * 0.5
					else math.sin(t * 2 + entry.phase) * 0.15
				local p = nextPosition + Vector3.new(0, bob, 0)
				model:PivotTo(CFrame.lookAt(p, p + entry.look))
			elseif entry.position then
				entry.position = nil
				model:PivotTo(HIDDEN)
			end
		end
	end
end

function Followers.start()
	folder = Instance.new("Folder")
	folder.Name = "NestHeistFollowers"
	folder.Parent = workspace

	local function watch(player: Player)
		rebuild(player)
		player:GetAttributeChangedSignal("Follower"):Connect(function()
			rebuild(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		local entry = followers[player]
		if entry and entry.model then
			entry.model:Destroy()
		end
		followers[player] = nil
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		update(math.min(dt, 0.1))
	end)
end

return Followers
