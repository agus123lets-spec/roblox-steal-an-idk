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

ClientState.start()
HUD.start()
Panels.start()
Reveal.start()
World.start()
Input.start()
