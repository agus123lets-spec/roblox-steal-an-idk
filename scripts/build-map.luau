-- Bakes the world into build/Map.rbxm so Rojo can place it in Workspace.
-- Run from the repository root: lune run scripts/build-map
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Loader = require("./lib/loader")

local MapBuilder = Loader.load("MapBuilder")

local map = MapBuilder.build()
local descendants = map:GetDescendants()
local parts = 0
for _, instance in descendants do
	if instance:IsA("BasePart") then
		parts += 1
	end
end

if not fs.isDir("build") then
	fs.writeDir("build")
end
fs.writeFile("build/Map.rbxm", roblox.serializeModel({ map }))
print(`Baked build/Map.rbxm: {#descendants} instances ({parts} parts)`)
