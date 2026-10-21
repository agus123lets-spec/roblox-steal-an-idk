--!strict
-- Each biome's guardian wakes up when someone carries an egg on its island and chases them.
-- Below the biome's recommended Speed you're slower than the guardian, so it acts as a soft gate.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerService = require(script.Parent.PlayerService)
local EggService = require(script.Parent.EggService)

type Guardian = {
	biome: Config.BiomeInfo,
	model: Model,
	home: Vector3,
	homeLook: Vector3,
	position: Vector3,
	look: Vector3,
	state: string, -- "idle" | "notice" | "chase" | "return" | "rest"
	target: Player?,
	stateUntil: number,
	eyes: { BasePart },
	eyeColors: { Color3 },
	stateLabel: TextLabel?,
	bobPhase: number,
	lastRender: number,
}

local GuardianService = {}

local guardians: { Guardian } = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function setState(guardian: Guardian, state: string, duration: number?)
	guardian.state = state
	guardian.stateUntil = PlayerService.now() + (duration or 0)
	local angry = state == "notice" or state == "chase"
	for i, eye in guardian.eyes do
		eye.Color = if angry then Color3.fromRGB(255, 50, 40) else guardian.eyeColors[i]
		eye.Material = if angry then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
	local label = guardian.stateLabel
	if label then
		label.Text = if state == "idle"
			then "💤"
			elseif state == "notice" then "❗"
			elseif state == "chase" then "😡 CHASING"
			elseif state == "rest" then "😤"
			else "..."
	end
end

local function alert(player: Player?, kind: string, guardian: Guardian)
	if player and player.Parent then
		Remotes.Guardian:FireClient(player, kind, guardian.biome.guardian.name)
	end
end

local function inBiome(guardian: Guardian, position: Vector3, extra: number): boolean
	return (flat(position) - flat(guardian.biome.center)).Magnitude <= guardian.biome.radius + extra
end

local function validTarget(guardian: Guardian, player: Player?): BasePart?
	if not player or not PlayerService.get(player) or not EggService.isCarrying(player) then
		return nil
	end
	local root = PlayerService.rootOf(player)
	if root and inBiome(guardian, root.Position, Config.Steal.leash) then
		return root
	end
	return nil
end

local function findTarget(guardian: Guardian): Player?
	local best: Player? = nil
	local bestDistance = math.huge
	for _, session in PlayerService.all() do
		local root = PlayerService.rootOf(session.player)
		if root and EggService.isCarrying(session.player) and inBiome(guardian, root.Position, 0) then
			local distance = (flat(root.Position) - flat(guardian.position)).Magnitude
			if distance < bestDistance then
				best = session.player
				bestDistance = distance
			end
		end
	end
	return best
end

local function moveToward(guardian: Guardian, goal: Vector3, speed: number, dt: number): number
	local offset = flat(goal) - flat(guardian.position)
	local distance = offset.Magnitude
	if distance > 0.05 then
		local step = math.min(distance, speed * dt)
		local nextPos = guardian.position + offset.Unit * step
		-- Stay on the island.
		local fromCenter = flat(nextPos) - flat(guardian.biome.center)
		local limit = guardian.biome.radius - 4
		if fromCenter.Magnitude > limit then
			nextPos = guardian.biome.center + fromCenter.Unit * limit
		end
		guardian.position = Vector3.new(nextPos.X, guardian.home.Y, nextPos.Z)
		guardian.look = offset.Unit
	end
	return distance
end

local function render(guardian: Guardian, t: number, moving: boolean)
	local bob = if moving
		then math.abs(math.sin(t * 9 + guardian.bobPhase)) * 0.7
		else math.sin(t * 1.6 + guardian.bobPhase) * 0.15
	local position = guardian.position + Vector3.new(0, bob, 0)
	guardian.model:PivotTo(CFrame.lookAt(position, position + guardian.look))
end

local function catch(guardian: Guardian, player: Player, root: BasePart)
	local session = PlayerService.get(player)
	EggService.guardianCatch(player)
	if session then
		session.data.stats.caught += 1
		local push = flat(root.Position - guardian.position)
		PlayerService.stun(session, Config.Steal.guardianStun, if push.Magnitude > 0.1 then push.Unit else nil)
	end
	alert(player, "caught", guardian)
	guardian.target = nil
	setState(guardian, "rest", 1.5)
end

local function step(guardian: Guardian, dt: number, t: number)
	local info = guardian.biome.guardian
	local moving = false

	if guardian.state == "idle" or guardian.state == "return" then
		local target = findTarget(guardian)
		if target then
			guardian.target = target
			setState(guardian, "notice", info.noticeDelay)
			alert(target, "chase", guardian)
		end
	end

	if guardian.state == "notice" then
		local root = validTarget(guardian, guardian.target)
		if not root then
			alert(guardian.target, "escaped", guardian)
			guardian.target = nil
			setState(guardian, "return")
		else
			local toTarget = flat(root.Position - guardian.position)
			if toTarget.Magnitude > 0.01 then
				guardian.look = toTarget.Unit
			end
			if t >= guardian.stateUntil then
				setState(guardian, "chase")
			end
		end
	elseif guardian.state == "chase" then
		local target = guardian.target
		local root = validTarget(guardian, target)
		if not target or not root then
			alert(target, "escaped", guardian)
			guardian.target = nil
			setState(guardian, "return")
		else
			local speed = info.speed * (if EggService.isCarryingJackpot(target) then 1.1 else 1)
			local distance = moveToward(guardian, root.Position, speed, dt)
			moving = true
			if distance <= info.catchRadius then
				catch(guardian, target, root)
			end
		end
	elseif guardian.state == "return" then
		local distance = moveToward(guardian, guardian.home, info.speed * 0.6, dt)
		moving = distance > 0.5
		if not moving then
			guardian.look = guardian.homeLook
			setState(guardian, "idle")
		end
	elseif guardian.state == "rest" then
		if t >= guardian.stateUntil then
			setState(guardian, "return")
		end
	end

	-- Idle guardians only need a gentle bob ten times a second.
	if moving or t - guardian.lastRender >= 0.1 then
		guardian.lastRender = t
		render(guardian, t, moving)
	end
end

function GuardianService.start()
	local map = workspace:FindFirstChild("Map")
	local biomes = map and map:FindFirstChild("Biomes")
	if not biomes then
		error("[NestHeist] Workspace.Map.Biomes is missing")
	end
	for _, biome in Config.Biomes do
		local biomeModel = biomes:FindFirstChild(biome.key)
		local model = biomeModel and biomeModel:FindFirstChild("Guardian")
		if model and model:IsA("Model") and model.PrimaryPart then
			local pivot = model:GetPivot()
			local eyes: { BasePart } = {}
			local eyeColors: { Color3 } = {}
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("BasePart") and descendant.Name == "Eye" then
					table.insert(eyes, descendant)
					table.insert(eyeColors, descendant.Color)
				end
			end
			local stateLabel = model:FindFirstChild("StateLabel", true)
			local look = flat(pivot.LookVector)
			local guardian: Guardian = {
				biome = biome,
				model = model,
				home = pivot.Position,
				homeLook = if look.Magnitude > 0 then look.Unit else Vector3.new(0, 0, -1),
				position = pivot.Position,
				look = if look.Magnitude > 0 then look.Unit else Vector3.new(0, 0, -1),
				state = "idle",
				target = nil,
				stateUntil = 0,
				eyes = eyes,
				eyeColors = eyeColors,
				stateLabel = if stateLabel and stateLabel:IsA("TextLabel") then stateLabel else nil,
				bobPhase = biome.order * 1.7,
				lastRender = 0,
			}
			setState(guardian, "idle")
			table.insert(guardians, guardian)
		else
			warn(`[NestHeist] No guardian found for {biome.key}`)
		end
	end

	RunService.Heartbeat:Connect(function(dt)
		local t = PlayerService.now()
		for _, guardian in guardians do
			step(guardian, math.min(dt, 0.1), t)
		end
	end)
end

return GuardianService
