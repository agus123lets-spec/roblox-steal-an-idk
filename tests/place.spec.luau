-- Inspects the built place file. Run scripts/build.sh first, then: lune run tests/place.spec
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local passes, failures = 0, 0
local function check(name: string, condition: boolean, detail: any?)
	if condition then
		passes += 1
	else
		failures += 1
		print(`FAIL {name}{if detail ~= nil then ": " .. tostring(detail) else ""}`)
	end
end

local PLACE = "build/NestHeist.rbxl"
if not fs.isFile(PLACE) then
	print(`Missing {PLACE}; run scripts/build.sh first`)
	process.exit(1)
end
local game = roblox.deserializePlace(fs.readFile(PLACE))

local function find(path: { string }): any
	local current: any = game
	for _, name in path do
		if current == nil then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

local function expectScripts(path: { string }, className: string, names: { string })
	local container = find(path)
	check(`{table.concat(path, ".")} exists`, container ~= nil)
	if not container then
		return
	end
	for _, name in names do
		local script = container:FindFirstChild(name)
		check(
			`{table.concat(path, ".")}.{name} is a {className}`,
			script ~= nil and script.ClassName == className,
			script and script.ClassName
		)
		if script then
			check(`{name} has source`, #script.Source > 50)
		end
	end
end

expectScripts(
	{ "ReplicatedStorage", "Shared" },
	"ModuleScript",
	{ "Config", "PetLogic", "Format", "Rng", "Builders", "MapBuilder", "Remotes" }
)
expectScripts({ "ServerScriptService", "Server" }, "Script", { "Main" })
expectScripts({ "ServerScriptService", "Server", "Services" }, "ModuleScript", {
	"DataService",
	"PlayerService",
	"PlotService",
	"EggService",
	"GuardianService",
	"TrainingService",
	"ToolService",
	"ShopService",
})
expectScripts({ "StarterPlayer", "StarterPlayerScripts", "Client" }, "LocalScript", { "Main" })
expectScripts({ "StarterPlayer", "StarterPlayerScripts", "Client", "Controllers" }, "ModuleScript", {
	"ClientState",
	"UIKit",
	"Sounds",
	"HUD",
	"Panels",
	"Reveal",
	"World",
	"Input",
})

expectScripts({ "ReplicatedStorage", "Shared" }, "ModuleScript", { "Progression" })
expectScripts({ "ServerScriptService", "Server", "Services" }, "ModuleScript", {
	"Loop",
	"EventState",
	"EventService",
	"RewardService",
	"ProgressionService",
	"LeaderboardService",
	"Actions",
})
expectScripts({ "StarterPlayer", "StarterPlayerScripts", "Client", "Controllers" }, "ModuleScript", { "Followers" })
expectScripts({ "StarterPlayer", "StarterPlayerScripts", "Client", "Controllers", "Pages" }, "ModuleScript", {
	"Types",
	"ShopPage",
	"PetsPage",
	"RewardsPage",
	"IndexPage",
	"RebirthPage",
})

local serverMain = find({ "ServerScriptService", "Server", "Main" })
local playerStart = serverMain and string.find(serverMain.Source, 'start("PlayerService", PlayerService)', 1, true)
local shopStart = serverMain and string.find(serverMain.Source, 'start("ShopService", ShopService)', 1, true)
check("server starts PlayerService last", playerStart ~= nil and shopStart ~= nil and playerStart > shopStart)

local workspace = game:GetService("Workspace")
check("streaming disabled", workspace.StreamingEnabled == false)
local map = workspace:FindFirstChild("Map")
check("Workspace.Map baked in", map ~= nil and map.ClassName == "Model")
if map then
	check("8 plots baked", #map.Plots:GetChildren() == 8)
	check("5 biomes baked", #map.Biomes:GetChildren() == 5)
	local boards = map.Hub:FindFirstChild("Leaderboards")
	check("leaderboards baked", boards ~= nil and #boards:GetChildren() == 4)
	check("spawn baked", map.Hub:FindFirstChild("Spawn") ~= nil)
	local parts = 0
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	check("map has plenty of parts", parts > 1000, parts)
end

local lighting = game:GetService("Lighting")
for _, className in { "Atmosphere", "BloomEffect", "ColorCorrectionEffect", "SunRaysEffect", "Sky" } do
	check(`Lighting has {className}`, lighting:FindFirstChildOfClass(className) ~= nil)
end
check("Lighting ClockTime set", math.abs(lighting.ClockTime - 14.5) < 0.01, lighting.ClockTime)

local starterPlayer = game:GetService("StarterPlayer")
check("JumpHeight mode", starterPlayer.CharacterUseJumpPower == false)
check("respawn time", game:GetService("Players").RespawnTime == 3)
check("one player per nest", game:GetService("Players").MaxPlayers == 8, game:GetService("Players").MaxPlayers)

print(`place.spec: {passes} passed, {failures} failed`)
if failures > 0 then
	process.exit(1)
end
