-- Client entry point.
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Controllers = script.Parent.Controllers

local ClientState = require(Controllers.ClientState)
local HUD = require(Controllers.HUD)
local Panels = require(Controllers.Panels)
local Reveal = require(Controllers.Reveal)
local World = require(Controllers.World)
local Input = require(Controllers.Input)
local Followers = require(Controllers.Followers)

local function start(name: string, controller: { start: () -> () })
	local ok, err = pcall(controller.start)
	if not ok then
		warn(`[NestHeist] {name} failed to start: {err}`)
	end
end

start("ClientState", ClientState)
start("HUD", HUD)
start("Input", Input)
start("Panels", Panels)
start("Reveal", Reveal)
start("World", World)
start("Followers", Followers)
