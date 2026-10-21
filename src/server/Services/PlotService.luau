--!strict
-- Assigns each player a nest (plot), shows their pets on pedestals and runs the base shield.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PetLogic = require(ReplicatedStorage.Shared.PetLogic)
local Builders = require(ReplicatedStorage.Shared.Builders)
local Format = require(ReplicatedStorage.Shared.Format)
local PlayerService = require(script.Parent.PlayerService)
local Loop = require(script.Parent.Loop)

type Session = PlayerService.Session

export type Plot = {
	index: number,
	model: Model,
	floor: BasePart,
	incubatorSpots: { BasePart },
	incubatorLabels: { TextLabel },
	pedestals: { BasePart },
	pedestalSpots: { BasePart },
	jogPad: BasePart,
	shieldPad: BasePart,
	shieldDome: BasePart,
	shieldStatus: TextLabel?,
	ownerLabel: TextLabel?,
	petsFolder: Instance,
	color: Color3,
	owner: Player?,
	shieldActive: boolean,
	shieldUntil: number,
	shieldReadyAt: number,
}

type ShieldCallback = (Plot) -> ()

local PlotService = {}

local plots: { Plot } = {}
local plotByPlayer: { [Player]: Plot } = {}
local shieldCallbacks: { ShieldCallback } = {}

local LOCKED_COLOR = Color3.fromRGB(90, 92, 110)

local function child(parent: Instance, name: string): Instance
	local found = parent:FindFirstChild(name)
	if not found then
		error(`[NestHeist] Map is missing {parent:GetFullName()}.{name}`)
	end
	return found
end

local function part(parent: Instance, name: string): BasePart
	local found = child(parent, name)
	if not found:IsA("BasePart") then
		error(`[NestHeist] {found:GetFullName()} should be a BasePart`)
	end
	return found
end

local function findLabel(container: Instance, name: string): TextLabel?
	local found = container:FindFirstChild(name, true)
	if found and found:IsA("TextLabel") then
		return found
	end
	return nil
end

local function loadPlots()
	local map = child(workspace, "Map")
	local folder = child(map, "Plots")
	for _, model in folder:GetChildren() do
		local index = model:GetAttribute("PlotIndex")
		if model:IsA("Model") and type(index) == "number" then
			local incubatorSpots: { BasePart } = {}
			local incubatorLabels: { TextLabel } = {}
			local incubators = child(model, "Incubators")
			for i = 1, #Config.Plots.incubatorOffsets do
				local incubator = child(incubators, "Incubator" .. i)
				local spot = part(incubator, "Spot")
				incubatorSpots[i] = spot
				local label = findLabel(spot, "Status")
				if label then
					incubatorLabels[i] = label
				end
			end
			local pedestals: { BasePart } = {}
			local pedestalSpots: { BasePart } = {}
			local pedestalFolder = child(model, "Pedestals")
			local count = #Config.Plots.pedestalColumns * #Config.Plots.pedestalRows
			for i = 1, count do
				local pedestal = part(pedestalFolder, "Pedestal" .. i)
				pedestals[i] = pedestal
				pedestalSpots[i] = part(pedestal, "Spot")
			end
			local shieldPad = part(model, "ShieldPad")
			local plot: Plot = {
				index = index,
				model = model,
				floor = part(model, "Floor"),
				incubatorSpots = incubatorSpots,
				incubatorLabels = incubatorLabels,
				pedestals = pedestals,
				pedestalSpots = pedestalSpots,
				jogPad = part(model, "JogPad"),
				shieldPad = shieldPad,
				shieldDome = part(model, "ShieldDome"),
				shieldStatus = findLabel(shieldPad, "Status"),
				ownerLabel = findLabel(model, "OwnerLabel"),
				petsFolder = child(model, "Pets"),
				color = Config.Plots.colors[index] or Color3.new(1, 1, 1),
				owner = nil,
				shieldActive = false,
				shieldUntil = 0,
				shieldReadyAt = 0,
			}
			table.insert(plots, plot)
		end
	end
	table.sort(plots, function(a, b)
		return a.index < b.index
	end)
end

---------------------------------------------------------------------------
-- Geometry helpers
---------------------------------------------------------------------------
function PlotService.isInside(plot: Plot, position: Vector3, margin: number): boolean
	local localPos = plot.floor.CFrame:PointToObjectSpace(position)
	local half = plot.floor.Size / 2
	return math.abs(localPos.X) <= half.X + margin
		and math.abs(localPos.Z) <= half.Z + margin
		and localPos.Y > -6
		and localPos.Y < 30
end

function PlotService.isOnPad(pad: BasePart, position: Vector3): boolean
	local localPos = pad.CFrame:PointToObjectSpace(position)
	local half = pad.Size / 2
	return math.abs(localPos.X) <= half.X + 0.5
		and math.abs(localPos.Z) <= half.Z + 0.5
		and localPos.Y > -1
		and localPos.Y < 7
end

function PlotService.getPlot(player: Player): Plot?
	return plotByPlayer[player]
end

function PlotService.getPlots(): { Plot }
	return plots
end

function PlotService.isShielded(player: Player): boolean
	local plot = plotByPlayer[player]
	return plot ~= nil and plot.shieldActive
end

function PlotService.onShieldChanged(callback: ShieldCallback)
	table.insert(shieldCallbacks, callback)
end

---------------------------------------------------------------------------
-- Pets on pedestals
---------------------------------------------------------------------------
local function render(session: Session)
	local plot = plotByPlayer[session.player]
	if not plot then
		return
	end
	plot.petsFolder:ClearAllChildren()
	local pets = table.clone(session.data.pets)
	table.sort(pets, function(a, b)
		return PetLogic.income(a) > PetLogic.income(b)
	end)
	for i, pedestal in plot.pedestals do
		local unlocked = i <= session.data.slots
		pedestal.Color = if unlocked then plot.color:Lerp(Color3.new(1, 1, 1), 0.55) else LOCKED_COLOR
		pedestal.Transparency = if unlocked then 0 else 0.55
		local pet = pets[i]
		if pet and unlocked then
			local info = Config.PetByKey[pet.kind]
			local sizeInfo = PetLogic.sizeInfo(pet.size)
			local scale = if sizeInfo then sizeInfo.scale else 1
			local model = Builders.pet(pet.kind, scale, pet.mutation, plot.pedestalSpots[i].CFrame)
			model:SetAttribute("PetId", pet.id)
			local root = model.PrimaryPart
			if root and info then
				local rarity = Config.Rarities[info.rarity]
				local gui = Builders.billboard(root, Vector3.new(0, 3.6 * scale + 1.2, 0), UDim2.fromScale(7, 2.2), 60)
				Builders.text(
					gui,
					"Name",
					PetLogic.describe(pet),
					UDim2.fromScale(1, 0.55),
					UDim2.fromScale(0, 0),
					rarity.color,
					Enum.Font.FredokaOne
				)
				Builders.text(
					gui,
					"Income",
					Format.money(PetLogic.income(pet)) .. "/s",
					UDim2.fromScale(1, 0.45),
					UDim2.fromScale(0, 0.55),
					Color3.fromRGB(255, 220, 90),
					Enum.Font.GothamBold
				)
			end
			model.Parent = plot.petsFolder
		end
	end
end

---------------------------------------------------------------------------
-- Ownership
---------------------------------------------------------------------------
local function teleportHome(session: Session, character: Model)
	local plot = plotByPlayer[session.player]
	if not plot then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or plotByPlayer[session.player] ~= plot then
		return
	end
	task.wait(0.1)
	if character.Parent then
		character:PivotTo(plot.floor.CFrame * CFrame.new(0, 4, -10))
	end
end

local function setShieldVisual(plot: Plot)
	plot.shieldDome.Transparency = if plot.shieldActive then 0.55 else 1
	plot.model:SetAttribute("ShieldUntil", if plot.shieldActive then plot.shieldUntil else 0)
	plot.model:SetAttribute("ShieldReadyAt", plot.shieldReadyAt)
	for _, callback in shieldCallbacks do
		task.spawn(callback, plot)
	end
end

local function assign(session: Session)
	for _, plot in plots do
		if plot.owner == nil then
			plot.owner = session.player
			plotByPlayer[session.player] = plot
			plot.model:SetAttribute("OwnerUserId", session.player.UserId)
			plot.model:SetAttribute("OwnerName", session.player.DisplayName)
			if plot.ownerLabel then
				plot.ownerLabel.Text = `{session.player.DisplayName}'s Nest`
			end
			plot.shieldActive = false
			plot.shieldUntil = 0
			plot.shieldReadyAt = 0
			setShieldVisual(plot)
			render(session)
			local character = session.player.Character
			if character then
				task.spawn(teleportHome, session, character)
			end
			return
		end
	end
	PlayerService.notify(session.player, "Every nest is taken on this server. Try another server!", "danger")
end

local function release(session: Session)
	local plot = plotByPlayer[session.player]
	if not plot then
		return
	end
	plotByPlayer[session.player] = nil
	plot.owner = nil
	plot.petsFolder:ClearAllChildren()
	plot.model:SetAttribute("OwnerUserId", nil)
	plot.model:SetAttribute("OwnerName", nil)
	if plot.ownerLabel then
		plot.ownerLabel.Text = "Empty Nest"
	end
	for _, pedestal in plot.pedestals do
		pedestal.Color = Color3.new(1, 1, 1)
		pedestal.Transparency = 0
	end
	plot.shieldActive = false
	plot.shieldUntil = 0
	plot.shieldReadyAt = 0
	setShieldVisual(plot)
end

---------------------------------------------------------------------------
-- Shield
---------------------------------------------------------------------------
local labelTimer = 0

local function shieldTick(dt: number)
	labelTimer += dt
	local now = PlayerService.now()
	for _, plot in plots do
		local owner = plot.owner
		if owner then
			if plot.shieldActive and now >= plot.shieldUntil then
				plot.shieldActive = false
				setShieldVisual(plot)
				PlayerService.notify(owner, "Your shield is down. Recharging...", "warn")
			elseif not plot.shieldActive and now >= plot.shieldReadyAt then
				local root = PlayerService.rootOf(owner)
				if root and PlotService.isOnPad(plot.shieldPad, root.Position) then
					plot.shieldActive = true
					plot.shieldUntil = now + Config.Steal.shieldDuration
					plot.shieldReadyAt = plot.shieldUntil + Config.Steal.shieldCooldown
					setShieldVisual(plot)
					PlayerService.notify(
						owner,
						`🛡 Shield up for {Config.Steal.shieldDuration}s. Your incubating eggs can't be stolen!`,
						"success"
					)
				end
			end
		end
	end
	if labelTimer >= 0.5 then
		labelTimer = 0
		for _, plot in plots do
			local label = plot.shieldStatus
			if label then
				local text
				if not plot.owner then
					text = "Step here to protect your eggs"
				elseif plot.shieldActive then
					text = `ACTIVE {Format.clock(plot.shieldUntil - now)}`
				elseif now < plot.shieldReadyAt then
					text = `Recharging {Format.clock(plot.shieldReadyAt - now)}`
				else
					text = "READY - step here!"
				end
				if label.Text ~= text then
					label.Text = text
				end
			end
		end
	end
end

function PlotService.start()
	loadPlots()
	PlayerService.onSessionStarted(assign)
	PlayerService.onSessionEnding(release)
	PlayerService.onPetsChanged(render)
	PlayerService.onCharacterSpawned(teleportHome)
	Loop.every("Shield", 0.1, shieldTick)
end

return PlotService
