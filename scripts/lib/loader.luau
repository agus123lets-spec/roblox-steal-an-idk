-- Loads Roblox-style ModuleScripts from src/shared under Lune.
-- `script.Parent.X` resolves to a sibling module and Roblox datatypes come from @lune/roblox,
-- so the same Config/Builders/MapBuilder code runs here and inside Roblox.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local SHARED_DIR = "src/shared"

local Loader = {}

local cache: { [string]: any } = {}

local sharedProxy = setmetatable({ Name = "Shared" }, {
	__index = function(_, key)
		return { Name = key, __module = true }
	end,
})

local loadModule: (name: string) -> any

local function fakeRequire(target: any): any
	if type(target) == "table" and target.__module then
		return loadModule(target.Name)
	end
	error("Unsupported require target in Lune loader: " .. tostring(target))
end

local robloxGlobals = {
	"Instance",
	"Vector2",
	"Vector3",
	"CFrame",
	"Color3",
	"ColorSequence",
	"ColorSequenceKeypoint",
	"NumberSequence",
	"NumberSequenceKeypoint",
	"NumberRange",
	"UDim",
	"UDim2",
	"Enum",
	"Font",
	"BrickColor",
	"Rect",
	"PhysicalProperties",
}

loadModule = function(name: string): any
	if cache[name] ~= nil then
		return cache[name]
	end
	local path = `{SHARED_DIR}/{name}.luau`
	local source = fs.readFile(path)
	local env: { [string]: any } = {
		script = { Name = name, Parent = sharedProxy },
		require = fakeRequire,
	}
	for _, global in robloxGlobals do
		env[global] = (roblox :: any)[global]
	end
	local chunk = luau.load(source, { debugName = path, environment = env })
	local result = chunk()
	cache[name] = result
	return result
end

Loader.load = loadModule

return Loader
