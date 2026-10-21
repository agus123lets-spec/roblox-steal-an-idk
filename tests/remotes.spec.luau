-- Contract test: every remote declared in Remotes.luau is both sent and handled somewhere,
-- so a renamed or forgotten remote fails here instead of silently in game.
-- Run: lune run tests/remotes.spec
local fs = require("@lune/fs")
local process = require("@lune/process")

local passes, failures = 0, 0
local function check(name: string, condition: boolean)
	if condition then
		passes += 1
	else
		failures += 1
		print(`FAIL {name}`)
	end
end

local sources: { string } = {}
local function collect(dir: string)
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			collect(path)
		elseif string.sub(name, -5) == ".luau" and name ~= "Remotes.luau" then
			table.insert(sources, fs.readFile(path))
		end
	end
end
collect("src")
local all = table.concat(sources, "\n")

local function uses(pattern: string): boolean
	return string.find(all, pattern, 1, true) ~= nil
end

local remotes = fs.readFile("src/shared/Remotes.luau")
local events, functions = 0, 0
for name, kind in string.gmatch(remotes, '\n%s*(%w+) = (%a+)%("') do
	if kind == "event" then
		events += 1
		local fired = uses(`Remotes.{name}:FireClient(`)
			or uses(`Remotes.{name}:FireAllClients(`)
			or uses(`Remotes.{name}:FireServer(`)
		local handled = uses(`Remotes.{name}.OnClientEvent`) or uses(`Remotes.{name}.OnServerEvent`)
		check(`{name} is fired`, fired)
		check(`{name} is handled`, handled)
	elseif kind == "func" then
		functions += 1
		check(`{name} is invoked`, uses(`Remotes.{name}:InvokeServer(`))
		check(`{name} has a server handler`, uses(`Remotes.{name}.OnServerInvoke`))
	end
end
check("found the remote events", events == 12)
check("found the remote functions", functions == 2)

print(`remotes.spec: {passes} passed, {failures} failed`)
if failures > 0 then
	process.exit(1)
end
