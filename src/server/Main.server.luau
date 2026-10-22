-- Server entry point: makes sure the world exists, then starts every service.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Services = script.Parent.Services

if not workspace:FindFirstChild("Map") then
	-- The map is normally baked into the place file; rebuild it if someone deleted it.
	local MapBuilder = require(Shared.MapBuilder)
	MapBuilder.build().Parent = workspace
end

require(Shared.Remotes)

local PlayerService = require(Services.PlayerService)
local PlotService = require(Services.PlotService)
local EggService = require(Services.EggService)
local GuardianService = require(Services.GuardianService)
local TrainingService = require(Services.TrainingService)
local ToolService = require(Services.ToolService)
local ShopService = require(Services.ShopService)
local RewardService = require(Services.RewardService)
local ProgressionService = require(Services.ProgressionService)
local EventService = require(Services.EventService)
local LeaderboardService = require(Services.LeaderboardService)
local Actions = require(Services.Actions)

local function start(name: string, service: { start: () -> () })
	local ok, err = pcall(service.start)
	if not ok then
		warn(`[NestHeist] {name} failed to start: {err}`)
	end
end

start("PlotService", PlotService)
start("EggService", EggService)
start("GuardianService", GuardianService)
start("TrainingService", TrainingService)
start("ToolService", ToolService)
start("ShopService", ShopService)
start("RewardService", RewardService)
start("ProgressionService", ProgressionService)
start("EventService", EventService)
start("LeaderboardService", LeaderboardService)
start("Actions", Actions)
-- Last, so every service has registered its session hooks before the first player loads.
start("PlayerService", PlayerService)

print("[NestHeist] Server ready")
