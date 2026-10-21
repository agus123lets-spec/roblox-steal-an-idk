--!strict
-- Player input: the Dash ability (Q / gamepad L1 / mobile button) and tool activation.

local ContextActionService: ContextActionService = game:GetService("ContextActionService")
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local HUD = require(script.Parent.HUD)
local Sounds = require(script.Parent.Sounds)

local player = Players.LocalPlayer

local Input = {}

local dashReadyAt = 0
local hooked: { [Tool]: boolean } = {}
local lastToolUse = 0

local function dash(_actionName: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local now = os.clock()
	if now < dashReadyAt then
		return Enum.ContextActionResult.Sink
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootInstance = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootInstance or not rootInstance:IsA("BasePart") then
		return Enum.ContextActionResult.Sink
	end
	local root = rootInstance
	if humanoid.WalkSpeed <= 0 or humanoid.PlatformStand or humanoid.Health <= 0 then
		return Enum.ContextActionResult.Sink
	end
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = root.CFrame.LookVector
	end
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.01 then
		return Enum.ContextActionResult.Sink
	end
	direction = direction.Unit

	local speed = math.max(humanoid.WalkSpeed * Config.Dash.factor, Config.Dash.minSpeed)
	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "Dash"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.MaxForce = math.huge
	velocity.VectorVelocity = direction * speed
	velocity.Parent = root
	task.delay(Config.Dash.duration, function()
		velocity:Destroy()
		attachment:Destroy()
	end)

	dashReadyAt = now + Config.Dash.cooldown
	HUD.dashUsed(Config.Dash.cooldown)
	Sounds.play("dash")
	return Enum.ContextActionResult.Sink
end

local function hookTool(tool: Instance)
	if not tool:IsA("Tool") or hooked[tool] then
		return
	end
	local key = tool:GetAttribute("ToolKey")
	if type(key) ~= "string" then
		return
	end
	hooked[tool] = true
	tool.Activated:Connect(function()
		if os.clock() - lastToolUse < 0.25 then
			return
		end
		lastToolUse = os.clock()
		local mouse = player:GetMouse()
		Remotes.UseTool:FireServer(key, mouse.Hit.Position)
	end)
	tool.Destroying:Connect(function()
		hooked[tool] = nil
	end)
end

local function watchContainer(container: Instance)
	for _, child in container:GetChildren() do
		hookTool(child)
	end
	container.ChildAdded:Connect(hookTool)
end

function Input.start()
	ContextActionService:BindAction("NestHeistDash", dash, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
	ContextActionService:SetTitle("NestHeistDash", "Dash")

	local backpack = player:WaitForChild("Backpack")
	watchContainer(backpack)
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			watchContainer(child)
		end
	end)
	if player.Character then
		watchContainer(player.Character)
	end
	player.CharacterAdded:Connect(watchContainer)
end

return Input
