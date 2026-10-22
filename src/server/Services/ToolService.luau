--!strict
-- Heist tools. Net Launcher: knocks the egg off a carrier. Slime Puddle: slows carriers.
-- Both only affect players carrying an egg, so nobody can be bullied while just walking around.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Builders = require(ReplicatedStorage.Shared.Builders)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerService = require(script.Parent.PlayerService)
local EggService = require(script.Parent.EggService)
local RewardService = require(script.Parent.RewardService)
local Loop = require(script.Parent.Loop)

type Session = PlayerService.Session

type Puddle = {
	owner: Player,
	part: BasePart,
	position: Vector3,
	expires: number,
}

local ToolService = {}

local cooldowns: { [Player]: { [string]: number } } = {}
local puddles: { Puddle } = {}

local TOOL_ORDER = { "Net", "Slime" }

local function owns(session: Session, key: string): boolean
	return key == "Net" or session.data.tools[key] == true
end

local function makeTool(key: string): Tool
	local info = if key == "Net" then Config.Tools.Net else Config.Tools.Slime
	local tool = Instance.new("Tool")
	tool.Name = info.name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = if key == "Net"
		then "Click a carrier to knock their egg loose"
		else "Click the ground to drop a slowing slime puddle"
	tool:SetAttribute("ToolKey", key)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = if key == "Net" then Vector3.new(0.6, 0.6, 2.8) else Vector3.new(1.2, 1.2, 1.2)
	handle.Color = if key == "Net" then Color3.fromRGB(90, 200, 120) else Color3.fromRGB(150, 255, 90)
	handle.Material = if key == "Net" then Enum.Material.SmoothPlastic else Enum.Material.Neon
	handle.Massless = true
	handle.CanCollide = false
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	if key == "Slime" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = handle
	end
	handle.Parent = tool
	return tool
end

function ToolService.giveTools(player: Player)
	local session = PlayerService.get(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		local waited = player:WaitForChild("Backpack", 5)
		backpack = if waited and waited:IsA("Backpack") then waited else nil
	end
	if not session or not backpack then
		return
	end
	for _, key in TOOL_ORDER do
		local name = if key == "Net" then Config.Tools.Net.name else Config.Tools.Slime.name
		local character = player.Character
		local has = backpack:FindFirstChild(name) or (character and character:FindFirstChild(name))
		if owns(session, key) and not has then
			makeTool(key).Parent = backpack
		end
	end
end

local function cooldownReady(player: Player, key: string, duration: number): boolean
	local list = cooldowns[player]
	if not list then
		list = {}
		cooldowns[player] = list
	end
	local t = PlayerService.now()
	if (list[key] or 0) > t then
		return false
	end
	list[key] = t + duration
	return true
end

local function lineOfSight(from: Vector3, to: Vector3, ignore: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local result = workspace:Raycast(from, to - from, params)
	return result == nil
end

local function useNet(session: Session, root: BasePart, aim: Vector3)
	local info = Config.Tools.Net
	local player = session.player
	local origin = root.Position
	local direction = aim - origin
	if direction.Magnitude < 0.1 then
		return
	end
	direction = direction.Unit
	local minDot = math.cos(math.rad(info.coneDegrees))

	-- Lenient aim assist: best target inside the cone, carriers preferred.
	local best: Session? = nil
	local bestScore = math.huge
	for _, other in PlayerService.all() do
		if other.player ~= player then
			local otherRoot = PlayerService.rootOf(other.player)
			if otherRoot then
				local offset = otherRoot.Position - origin
				local distance = offset.Magnitude
				if distance <= info.range and distance > 0.1 then
					local dot = offset.Unit:Dot(direction)
					if dot >= minDot or distance < 6 then
						local score = distance * (2 - dot) * (if EggService.isCarrying(other.player) then 0.5 else 1)
						if score < bestScore then
							best = other
							bestScore = score
						end
					end
				end
			end
		end
	end

	local hitPosition = origin + direction * info.range
	if best then
		local targetRoot = PlayerService.rootOf(best.player)
		local ignore: { Instance } = {}
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(ignore, p.Character)
			end
		end
		local eggs = workspace:FindFirstChild("Eggs")
		if eggs then
			table.insert(ignore, eggs)
		end
		if targetRoot and lineOfSight(origin, targetRoot.Position, ignore) then
			hitPosition = targetRoot.Position
			if not EggService.isCarrying(best.player) then
				PlayerService.notify(player, "The net bounced off. Only egg carriers can be netted!", "info")
			else
				local allowed, reason = PlayerService.canTarget(session, best)
				if not allowed then
					PlayerService.notify(player, reason or "You can't net that player.", "warn")
				elseif EggService.knockLoose(best.player) then
					RewardService.progress(session, "Net", 1)
					local push = Vector3.new(direction.X, 0, direction.Z)
					PlayerService.stun(best, info.stun, if push.Magnitude > 0.1 then push.Unit else nil)
					PlayerService.notify(
						best.player,
						`🕸 {player.DisplayName} netted you! Your egg fell. Grab it back!`,
						"danger"
					)
					PlayerService.notify(player, `🕸 Netted {best.player.DisplayName}! Grab their egg!`, "success")
				end
			end
		end
	end
	Remotes.FX:FireAllClients("Net", origin, hitPosition)
end

local function useSlime(session: Session, root: BasePart, aim: Vector3)
	local info = Config.Tools.Slime
	local player = session.player
	local offset = aim - root.Position
	if offset.Magnitude > info.range then
		aim = root.Position + offset.Unit * info.range
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(aim + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), params)
	if not result then
		PlayerService.notify(player, "Aim the slime at the ground.", "info")
		return
	end

	-- Keep at most maxActive puddles per player.
	local mine = {}
	for index, puddle in puddles do
		if puddle.owner == player then
			table.insert(mine, index)
		end
	end
	if #mine >= info.maxActive then
		local oldest = puddles[mine[1]]
		oldest.part:Destroy()
		table.remove(puddles, mine[1])
	end

	local position = result.Position
	local part = Builders.cylinder(
		workspace,
		"SlimePuddle",
		0.3,
		info.radius * 2,
		CFrame.new(position + Vector3.new(0, 0.12, 0)),
		Color3.fromRGB(140, 255, 90),
		Enum.Material.Neon
	)
	part.Transparency = 0.3
	part.CastShadow = false
	Builders.noCollide(part)
	local puddle: Puddle =
		{ owner = player, part = part, position = position, expires = PlayerService.now() + info.lifetime }
	table.insert(puddles, puddle)
	Remotes.FX:FireAllClients("Slime", position)
end

local function puddleTick()
	local info = Config.Tools.Slime
	local t = PlayerService.now()
	for index = #puddles, 1, -1 do
		local puddle = puddles[index]
		if t >= puddle.expires or not puddle.owner.Parent then
			puddle.part:Destroy()
			table.remove(puddles, index)
		else
			local ownerSession = PlayerService.get(puddle.owner)
			for _, session in PlayerService.all() do
				if session.player ~= puddle.owner and EggService.isCarrying(session.player) then
					local root = PlayerService.rootOf(session.player)
					if root then
						local flatDistance = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(
							puddle.position.X,
							0,
							puddle.position.Z
						)).Magnitude
						local allowed = ownerSession == nil or (PlayerService.canTarget(ownerSession, session))
						if
							flatDistance <= info.radius
							and math.abs(root.Position.Y - puddle.position.Y) < 5
							and allowed
						then
							if t >= session.slowUntil then
								PlayerService.notify(session.player, "You're stuck in slime!", "warn")
							end
							PlayerService.slow(session, info.slowFactor, info.slowDuration)
						end
					end
				end
			end
		end
	end
end

local function onUseTool(player: Player, key: any, aim: any)
	if type(key) ~= "string" or typeof(aim) ~= "Vector3" then
		return
	end
	local magnitude = aim.Magnitude
	if magnitude ~= magnitude or magnitude > 1e5 then
		return -- NaN or absurd aim from a modified client
	end
	local session = PlayerService.get(player)
	local root = PlayerService.rootOf(player)
	if not session or not root or not owns(session, key) or PlayerService.isStunned(session) then
		return
	end
	local info = if key == "Net" then Config.Tools.Net elseif key == "Slime" then Config.Tools.Slime else nil
	if not info then
		return
	end
	local character = player.Character
	local equipped = character and character:FindFirstChild(info.name)
	if not equipped or not equipped:IsA("Tool") then
		return
	end
	if not cooldownReady(player, key, info.cooldown) then
		return
	end
	if key == "Net" then
		useNet(session, root, aim)
	else
		useSlime(session, root, aim)
	end
end

function ToolService.start()
	Remotes.UseTool.OnServerEvent:Connect(onUseTool)
	PlayerService.onCharacterSpawned(function(session: Session, _character: Model)
		task.wait(0.2)
		ToolService.giveTools(session.player)
	end)
	PlayerService.onSessionStarted(function(session: Session)
		ToolService.giveTools(session.player)
	end)
	PlayerService.onSessionEnding(function(session: Session)
		cooldowns[session.player] = nil
	end)
	Loop.every("Slime", 0.1, puddleTick)
end

return ToolService
