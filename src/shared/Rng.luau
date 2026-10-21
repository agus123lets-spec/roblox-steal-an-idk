--!strict
-- Small deterministic random generator (Park-Miller). The map builder uses it so the
-- world looks identical in Studio, in the baked place file and in the runtime fallback.

export type Rng = {
	next: () -> number,
	range: (min: number, max: number) -> number,
	int: (min: number, max: number) -> number,
}

local Rng = {}

function Rng.new(seed: number): Rng
	local state = math.floor(math.abs(seed)) % 2147483646 + 1

	local function nextNumber(): number
		state = (state * 16807) % 2147483647
		return (state - 1) / 2147483646
	end

	return {
		next = nextNumber,
		range = function(min: number, max: number): number
			return min + (max - min) * nextNumber()
		end,
		int = function(min: number, max: number): number
			return math.min(max, min + math.floor((max - min + 1) * nextNumber()))
		end,
	}
end

return Rng
