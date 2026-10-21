--!strict
-- Runs `step` forever, every `interval` seconds. A failing tick is logged instead of
-- silently killing the loop for the rest of the server's life.

local Loop = {}

function Loop.every(name: string, interval: number, step: (dt: number) -> (), firstDelay: number?)
	task.spawn(function()
		local function run(dt: number)
			local ok, err = pcall(function(): string?
				step(dt)
				return nil
			end)
			if not ok then
				warn(`[NestHeist] {name} loop error: {err}`)
			end
		end
		if firstDelay then
			task.wait(firstDelay)
			run(0)
		end
		local last = os.clock()
		while true do
			task.wait(interval)
			local now = os.clock()
			run(now - last)
			last = now
		end
	end)
end

return Loop
