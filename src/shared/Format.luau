--!strict
-- Number and time formatting shared by server messages and the client UI.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc" }

local function trimZeros(text: string): string
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

-- 999 -> "999", 1234 -> "1.23K", 45600000 -> "45.6M". Always rounds down so we never overstate.
function Format.short(value: number): string
	if value ~= value then
		return "0"
	end
	local negative = value < 0
	local n = math.abs(value)
	local text: string
	if n < 1000 then
		if n == math.floor(n) or n >= 100 then
			text = tostring(math.floor(n))
		else
			text = trimZeros(string.format("%.1f", math.floor(n * 10) / 10))
		end
	else
		-- Loop instead of log10 so exact powers of 1000 never land in the wrong tier.
		local tier = 0
		while tier < #SUFFIXES - 1 and n >= 1000 ^ (tier + 1) do
			tier += 1
		end
		local scaled = n / 1000 ^ tier
		local epsilon = 1e-9
		if scaled >= 100 then
			text = tostring(math.floor(scaled + epsilon))
		elseif scaled >= 10 then
			text = trimZeros(string.format("%.1f", math.floor(scaled * 10 + epsilon) / 10))
		else
			text = trimZeros(string.format("%.2f", math.floor(scaled * 100 + epsilon) / 100))
		end
		text ..= SUFFIXES[tier + 1]
	end
	return if negative then "-" .. text else text
end

function Format.money(value: number): string
	return "$" .. Format.short(value)
end

-- 65 -> "1:05", 9 -> "0:09"
function Format.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

function Format.seconds(seconds: number): string
	return string.format("%.1fs", math.max(0, seconds))
end

return Format
