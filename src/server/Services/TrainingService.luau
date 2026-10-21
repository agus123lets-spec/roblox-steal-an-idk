--!strict
-- Speed training: laps on the Training Track (active, rewarding) and the Jog Pad in each nest (idle).

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PetLogic = require(ReplicatedStorage.Shared.PetLogic)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerService = require(script.Parent.PlayerService)
local PlotService = require(script.Parent.PlotService)

type Session = PlayerService.Session

type Lap = {
	startedAt: number,
	lastAngle: number,
	progress: number, -- accumulated radians around the infield
}

local TrainingService = {}

local laps: { [Player]: Lap } = {}
local jogBank: { [Player]: number } = {}

local TAU = math.pi * 2

local function onTrack(position: Vector3): boolean
	local T = Config.Training
	local dx = math.abs(position.X - T.center.X)
	local dz = math.abs(position.Z - T.center.Z)
	local insideOuter = dx <= T.outerX / 2 + 1 and dz <= T.outerZ / 2 + 1
	local insideInfield = dx < T.innerX / 2 and dz < T.innerZ / 2
	return insideOuter and not insideInfield and position.Y > -2 and position.Y < 14
end

local function angleOf(position: Vector3): number
	local T = Config.Training
	return math.atan2(position.Z - T.center.Z, position.X - T.center.X)
end

local function wrap(angle: number): number
	while angle > math.pi do
		angle -= TAU
	end
	while angle < -math.pi do
		angle += TAU
	end
	return angle
end

local function startLap(player: Player, position: Vector3, t: number)
	laps[player] = { startedAt = t, lastAngle = angleOf(position), progress = 0 }
	Remotes.Lap:FireClient(player, { kind = "start", at = t })
end

local function completeLap(session: Session, lap: Lap, t: number)
	local player = session.player
	local lapTime = t - lap.startedAt
	local walkSpeed = PetLogic.walkSpeedFor(session.data.speed)
	if lapTime < PetLogic.minLapTime(walkSpeed) then
		Remotes.Lap:FireClient(player, { kind = "cancel", reason = "Too fast to be real!" })
		return
	end
	local reward, bonus = PetLogic.lapReward(PlayerService.trainingMultiplier(session), lapTime, walkSpeed)
	PlayerService.addSpeed(session, reward)
	local stats = session.data.stats
	stats.laps += 1
	local best = stats.bestLap == 0 or lapTime < stats.bestLap
	if best then
		stats.bestLap = lapTime
	end
	Remotes.Lap:FireClient(player, {
		kind = "complete",
		time = lapTime,
		reward = reward,
		bonus = bonus,
		best = best,
		bestTime = stats.bestLap,
	})
end

local function trackTick(t: number)
	for _, session in PlayerService.all() do
		local player = session.player
		local root = PlayerService.rootOf(player)
		local lap = laps[player]
		if root and onTrack(root.Position) then
			if not lap then
				startLap(player, root.Position, t)
			else
				local angle = angleOf(root.Position)
				lap.progress += wrap(angle - lap.lastAngle)
				lap.lastAngle = angle
				if math.abs(lap.progress) >= TAU then
					completeLap(session, lap, t)
					startLap(player, root.Position, t)
				end
			end
		elseif lap then
			laps[player] = nil
			if math.abs(lap.progress) > math.pi / 2 then
				Remotes.Lap:FireClient(player, { kind = "cancel", reason = "You left the track!" })
			else
				Remotes.Lap:FireClient(player, { kind = "stop" })
			end
		end
	end
end

local function jogTick(dt: number)
	for _, session in PlayerService.all() do
		local player = session.player
		local root = PlayerService.rootOf(player)
		local plot = PlotService.getPlot(player)
		if root and plot and PlotService.isOnPad(plot.jogPad, root.Position) then
			session.speedRemainder += Config.Training.jogRate * PlayerService.trainingMultiplier(session) * dt
			local whole = math.floor(session.speedRemainder)
			if whole >= 1 then
				session.speedRemainder -= whole
				PlayerService.addSpeed(session, whole)
				jogBank[player] = (jogBank[player] or 0) + whole
			end
		end
	end
end

function TrainingService.start()
	PlayerService.onSessionEnding(function(session: Session)
		laps[session.player] = nil
		jogBank[session.player] = nil
	end)

	task.spawn(function()
		local floaterTimer = 0
		while true do
			local dt = task.wait(1 / 15)
			local t = PlayerService.now()
			trackTick(t)
			jogTick(dt)
			floaterTimer += dt
			if floaterTimer >= 1 then
				floaterTimer = 0
				for player, amount in jogBank do
					if player.Parent and amount > 0 then
						Remotes.Floater:FireClient(player, `+{Format.short(amount)} ⚡`, "speed")
					end
				end
				table.clear(jogBank)
			end
		end
	end)
end

return TrainingService
