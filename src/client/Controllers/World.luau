--!strict
-- World-space effects: "your nest" marker, path home while carrying, knockback, revenge highlight,
-- net/hatch/slime effects, bobbing pets, and hiding the steal prompt on your own eggs.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Builders = require(ReplicatedStorage.Shared.Builders)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sounds = require(script.Parent.Sounds)

local player = Players.LocalPlayer

local World = {}

local function rootOf(character: Model?): BasePart?
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function myPlot(): Model?
	local map = workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:IsA("Model") and plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- "Your nest" marker
---------------------------------------------------------------------------
local marker: BillboardGui? = nil

local function updateMarker()
	local plot = myPlot()
	local board = plot and plot:FindFirstChild("SignBoard")
	if not board or not board:IsA("BasePart") then
		return
	end
	if marker and marker.Parent == board then
		return
	end
	if marker then
		marker:Destroy()
	end
	local gui = Builders.billboard(board, Vector3.new(0, 12, 0), UDim2.fromOffset(200, 50), 3000)
	gui.Name = "HomeMarker"
	gui.AlwaysOnTop = true
	Builders.text(
		gui,
		"Text",
		"🏠 YOUR NEST",
		UDim2.fromScale(1, 1),
		UDim2.new(),
		Color3.fromRGB(255, 230, 120),
		Enum.Font.FredokaOne
	)
	marker = gui
end

---------------------------------------------------------------------------
-- Path home while carrying
---------------------------------------------------------------------------
local beam: Beam? = nil
local beamAttachments: { Attachment } = {}

local function clearBeam()
	if beam then
		beam:Destroy()
		beam = nil
	end
	for _, attachment in beamAttachments do
		attachment:Destroy()
	end
	table.clear(beamAttachments)
end

local function showBeam(rarity: string)
	clearBeam()
	local root = rootOf(player.Character)
	local plot = myPlot()
	local floor = plot and plot:FindFirstChild("Floor")
	if not root or not floor or not floor:IsA("BasePart") then
		return
	end
	local from = Instance.new("Attachment")
	from.Name = "HomeBeamFrom"
	from.Parent = root
	local to = Instance.new("Attachment")
	to.Name = "HomeBeamTo"
	to.Position = Vector3.new(0, 4, 0)
	to.Parent = floor
	local color = (Config.Rarities[rarity] or Config.Rarities.Common).color
	local created = Instance.new("Beam")
	created.Attachment0 = from
	created.Attachment1 = to
	created.Color = ColorSequence.new(color)
	created.Transparency = NumberSequence.new(0.25, 0.6)
	created.Width0 = 1.2
	created.Width1 = 2.5
	created.FaceCamera = true
	created.LightEmission = 1
	created.Segments = 20
	created.Parent = root
	beam = created
	beamAttachments = { from, to }
end

---------------------------------------------------------------------------
-- Knockback (guardian catch / net hit)
---------------------------------------------------------------------------
local function onKnockback(direction: any, duration: any)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootOf(character)
	if not humanoid or not root then
		return
	end
	local push = if typeof(direction) == "Vector3" then Vector3.new(direction.X, 0, direction.Z) else Vector3.zero
	if push.Magnitude > 0.01 then
		push = push.Unit * 38
	end
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = push + Vector3.new(0, 34, 0)
	local stunTime = if type(duration) == "number" then duration else 1
	task.delay(math.max(stunTime - 0.25, 0.4), function()
		if humanoid.Parent then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

---------------------------------------------------------------------------
-- Revenge highlight
---------------------------------------------------------------------------
local revengeTarget: Player? = nil
local revengeEnds = 0
local revengeHighlight: Highlight? = nil
local revengeTag: BillboardGui? = nil

local function clearRevengeVisuals()
	if revengeHighlight then
		revengeHighlight:Destroy()
		revengeHighlight = nil
	end
	if revengeTag then
		revengeTag:Destroy()
		revengeTag = nil
	end
end

local function applyRevengeVisuals()
	local target = revengeTarget
	local character = target and target.Character
	local root = rootOf(character)
	if not character or not root then
		return
	end
	if revengeHighlight and revengeHighlight.Parent == character then
		return
	end
	clearRevengeVisuals()
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(255, 60, 60)
	highlight.FillTransparency = 0.6
	highlight.OutlineColor = Color3.fromRGB(255, 230, 230)
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Adornee = character
	highlight.Parent = character
	revengeHighlight = highlight
	local tag = Builders.billboard(root, Vector3.new(0, 7, 0), UDim2.fromOffset(160, 40), 1000)
	tag.AlwaysOnTop = true
	Builders.text(
		tag,
		"Text",
		"🎯 THIEF",
		UDim2.fromScale(1, 1),
		UDim2.new(),
		Color3.fromRGB(255, 90, 90),
		Enum.Font.FredokaOne
	)
	revengeTag = tag
end

---------------------------------------------------------------------------
-- Effects
---------------------------------------------------------------------------
local fxFolder: Folder

local function burst(position: Vector3, color: Color3, count: number)
	local anchor = Instance.new("Part")
	anchor.Name = "Burst"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = fxFolder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.8
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(10, 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = anchor
	emitter:Emit(count)
	task.delay(1.5, function()
		anchor:Destroy()
	end)
end

local function netShot(from: Vector3, to: Vector3)
	local net = Instance.new("Part")
	net.Name = "Net"
	net.Anchored = true
	net.CanCollide = false
	net.CanQuery = false
	net.CanTouch = false
	net.Shape = Enum.PartType.Ball
	net.Size = Vector3.new(1.5, 1.5, 1.5)
	net.Material = Enum.Material.ForceField
	net.Color = Color3.fromRGB(120, 255, 160)
	net.CFrame = CFrame.new(from)
	net.Parent = fxFolder
	local distance = (to - from).Magnitude
	local travel = math.clamp(distance / 140, 0.08, 0.35)
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.min((os.clock() - start) / travel, 1)
		net.CFrame = CFrame.new(from:Lerp(to, alpha))
		net.Size = Vector3.one * (1.5 + alpha * 4)
		if alpha >= 1 then
			connection:Disconnect()
			net.Transparency = 0.3
			task.delay(0.25, function()
				net:Destroy()
			end)
		end
	end)
end

local function onFX(kind: any, a: any, b: any)
	if kind == "Net" and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
		netShot(a, b)
		local root = rootOf(player.Character)
		if root and (root.Position - a).Magnitude < 80 then
			Sounds.play("net")
		end
	elseif kind == "Hatch" and typeof(a) == "Vector3" then
		burst(a + Vector3.new(0, 2, 0), if typeof(b) == "Color3" then b else Color3.new(1, 1, 1), 45)
	elseif kind == "Steal" and typeof(a) == "Vector3" then
		burst(a, Color3.fromRGB(255, 80, 80), 25)
	elseif kind == "Deposit" and typeof(a) == "Vector3" then
		burst(a, Color3.fromRGB(120, 255, 140), 20)
		local root = rootOf(player.Character)
		if root and (root.Position - a).Magnitude < 40 then
			Sounds.play("deposit")
		end
	elseif kind == "Slime" and typeof(a) == "Vector3" then
		burst(a + Vector3.new(0, 1, 0), Color3.fromRGB(140, 255, 90), 20)
		local root = rootOf(player.Character)
		if root and (root.Position - a).Magnitude < 60 then
			Sounds.play("slime")
		end
	end
end

---------------------------------------------------------------------------
-- Bobbing pets (purely visual, client-side)
---------------------------------------------------------------------------
local petBases: { [Model]: { cf: CFrame, phase: number } } = {}

local function animatePets(t: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local map = workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	if not plots then
		return
	end
	local cameraPos = camera.CFrame.Position
	for _, plot in plots:GetChildren() do
		local pets = plot:FindFirstChild("Pets")
		local floor = plot:FindFirstChild("Floor")
		if pets and floor and floor:IsA("BasePart") and (floor.Position - cameraPos).Magnitude < 140 then
			for _, model in pets:GetChildren() do
				if model:IsA("Model") then
					local entry = petBases[model]
					if not entry then
						entry = { cf = model:GetPivot(), phase = math.random() * math.pi * 2 }
						petBases[model] = entry
					end
					local e = entry :: { cf: CFrame, phase: number }
					local bob = math.abs(math.sin(t * 2.2 + e.phase)) * 0.45
					local sway = math.sin(t * 0.9 + e.phase) * 0.3
					model:PivotTo(e.cf * CFrame.new(0, bob, 0) * CFrame.Angles(0, sway, 0))
				end
			end
		end
	end
	for model in petBases do
		if not model.Parent then
			petBases[model] = nil
		end
	end
end

---------------------------------------------------------------------------
-- Hide steal prompts on your own incubating eggs
---------------------------------------------------------------------------
local function processPrompt(instance: Instance)
	if instance:IsA("ProximityPrompt") and instance:GetAttribute("HideForUserId") == player.UserId then
		instance.MaxActivationDistance = 0
	end
end

function World.start()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "NestHeistFX"
	fxFolder.Parent = workspace

	local eggs = workspace:WaitForChild("Eggs")
	for _, descendant in eggs:GetDescendants() do
		processPrompt(descendant)
	end
	eggs.DescendantAdded:Connect(function(descendant)
		task.defer(processPrompt, descendant)
	end)

	Remotes.Carry.OnClientEvent:Connect(function(state: any, info: any)
		if state == "start" and type(info) == "table" then
			showBeam(tostring(info.rarity))
		else
			clearBeam()
		end
	end)
	player.CharacterAdded:Connect(function()
		clearBeam()
	end)

	Remotes.Knockback.OnClientEvent:Connect(onKnockback)
	Remotes.FX.OnClientEvent:Connect(onFX)
	Remotes.Revenge.OnClientEvent:Connect(function(thief: any, endsAt: any)
		if typeof(thief) == "Instance" and thief:IsA("Player") and type(endsAt) == "number" then
			revengeTarget = thief
			revengeEnds = endsAt
			applyRevengeVisuals()
		else
			revengeTarget = nil
			clearRevengeVisuals()
		end
	end)

	RunService.Heartbeat:Connect(function()
		animatePets(os.clock())
	end)

	task.spawn(function()
		while true do
			updateMarker()
			if revengeTarget then
				if workspace:GetServerTimeNow() > revengeEnds or not revengeTarget.Parent then
					revengeTarget = nil
					clearRevengeVisuals()
				else
					applyRevengeVisuals()
				end
			end
			task.wait(0.5)
		end
	end)
end

return World
