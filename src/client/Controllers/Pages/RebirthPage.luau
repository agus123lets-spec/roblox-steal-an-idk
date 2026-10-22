--!strict
-- Rebirth: trade coins, Speed and shoes for permanent income and training boosts.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Progression = require(ReplicatedStorage.Shared.Progression)
local UIKit = require(script.Parent.Parent.UIKit)
local Types = require(script.Parent.Types)

local C = UIKit.Colors

local function times(value: number): string
	local text = string.format("%.2f", value)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return "x" .. text
end

local function bar(ui: Types.UI, label: string, value: number, goal: number, color: Color3)
	local frame = UIKit.frame(ui.content, "Bar", UDim2.new(1, -8, 0, 56), UDim2.new(), C.row)
	frame.LayoutOrder = ui.order()
	UIKit.corner(frame)
	UIKit.stroke(frame, C.stroke, 2)
	local done = value >= goal
	local text = UIKit.label(
		frame,
		"Label",
		`{if done then "✅" else "⬜"} {label}: {Format.short(value)} / {Format.short(goal)}`,
		UDim2.new(1, -24, 0, 22),
		UDim2.fromOffset(12, 5),
		if done then C.good else C.text
	)
	text.TextXAlignment = Enum.TextXAlignment.Left
	local track = UIKit.frame(frame, "Track", UDim2.new(1, -24, 0, 14), UDim2.fromOffset(12, 33), C.panel)
	UIKit.corner(track, UDim.new(1, 0))
	local fill = UIKit.frame(track, "Fill", UDim2.fromScale(math.clamp(value / goal, 0, 1), 1), UDim2.new(), color)
	UIKit.corner(fill, UDim.new(1, 0))
end

local function ready(rebirths: number, coins: number, speed: number): boolean
	local coinsNeeded, speedNeeded = Progression.rebirthRequirement(rebirths)
	return coins >= coinsNeeded and speed >= speedNeeded
end

local Page: Types.Page = {
	title = "♻️ Rebirth",
	signature = function(state, _tab)
		local coinsNeeded, speedNeeded = Progression.rebirthRequirement(state.rebirths)
		local coinsStep = math.floor(math.clamp(state.coins / coinsNeeded, 0, 1) * 40)
		local speedStep = math.floor(math.clamp(state.speed / speedNeeded, 0, 1) * 40)
		return `{state.rebirths}|{coinsStep}|{speedStep}`
	end,
	render = function(ui, state, _tab)
		local r = state.rebirths
		local coinsNeeded, speedNeeded = Progression.rebirthRequirement(r)
		ui.row(
			`♻️ Rebirth {r}`,
			`Now: income {times(Progression.rebirthIncomeMultiplier(r))} • training {times(
				Progression.rebirthTrainingMultiplier(r)
			)}`,
			C.rare
		)
		bar(ui, "Coins", state.coins, coinsNeeded, C.coins)
		bar(ui, "Speed", state.speed, speedNeeded, C.speed)
		local canRebirth = ready(r, state.coins, state.speed)
		ui.row(
			`Next: Rebirth {r + 1}`,
			`Income {times(Progression.rebirthIncomeMultiplier(r + 1))} • training {times(
				Progression.rebirthTrainingMultiplier(r + 1)
			)} • +{Config.Rebirth.feathers} 🪶`,
			C.coins,
			if not canRebirth then "Not yet" elseif ui.pending("rebirth") then "Sure? Go!" else "Rebirth!",
			if not canRebirth then C.buttonDisabled elseif ui.pending("rebirth") then C.danger else C.rare,
			if canRebirth
				then function()
					if ui.confirm("rebirth") then
						ui.action("Rebirth", nil)
					end
				end
				else nil
		)
		ui.row("🔄 Resets", "Coins, Speed and Shoes", C.warn)
		ui.row("💎 You keep", "Pets, pen slots, tools, feathers, trails, themes and your Index", C.good)
	end,
	badge = function(state)
		return ready(state.rebirths, state.coins, state.speed)
	end,
}

return Page
