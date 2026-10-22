--!strict
-- Shop: shoes and pen slots, tools, and the Feathers shop (boosts, trails, nest themes).

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PetLogic = require(ReplicatedStorage.Shared.PetLogic)
local UIKit = require(script.Parent.Parent.UIKit)
local Types = require(script.Parent.Types)

local C = UIKit.Colors

local function keys(map: { [string]: boolean }): string
	local list = {}
	for key in map do
		table.insert(list, key)
	end
	table.sort(list)
	return table.concat(list, ",")
end

local Page: Types.Page = {
	title = "🛒 Shop",
	tabs = { "Upgrades", "Tools", "Feathers" },
	signature = function(state, tab)
		local nextShoes = Config.Shoes[state.shoesLevel + 1]
		local slotCost = PetLogic.slotCost(state.slots)
		local parts = {
			tostring(state.shoesLevel),
			tostring(state.slots),
			tostring(nextShoes ~= nil and state.coins >= nextShoes.cost),
			tostring(slotCost ~= nil and state.coins >= slotCost),
		}
		if tab == "Tools" then
			table.insert(parts, tostring(state.coins >= Config.Tools.Slime.cost))
			table.insert(parts, keys(state.tools))
		elseif tab == "Feathers" then
			table.insert(parts, tostring(state.feathers))
			table.insert(parts, keys(state.trails) .. state.equippedTrail)
			table.insert(parts, keys(state.themes) .. state.equippedTheme)
			-- Boost timers are shown here; refresh them every few seconds.
			table.insert(parts, tostring(math.floor(workspace:GetServerTimeNow() / 5)))
		end
		return table.concat(parts, "|")
	end,
	render = function(ui, state, tab)
		if tab == "Upgrades" then
			local shoes = Config.Shoes[state.shoesLevel]
			local nextShoes = Config.Shoes[state.shoesLevel + 1]
			if nextShoes then
				ui.row(
					`👟 {shoes.name} (x{Format.short(shoes.mult)})`,
					`Next: {nextShoes.name} - x{Format.short(nextShoes.mult)} Speed from training`,
					C.speed,
					Format.money(nextShoes.cost),
					if state.coins >= nextShoes.cost then C.button else C.buttonDisabled,
					function()
						ui.purchase("Shoes")
					end
				)
			else
				ui.row(
					`👟 {shoes.name} (x{Format.short(shoes.mult)})`,
					"Best shoes in the game!",
					C.speed,
					"MAX",
					C.buttonDisabled,
					nil
				)
			end
			local slotCost = PetLogic.slotCost(state.slots)
			if slotCost then
				ui.row(
					`🐾 Pen Slots {state.slots}/{Config.Plots.maxSlots}`,
					"Room for one more earning pet",
					C.coins,
					Format.money(slotCost),
					if state.coins >= slotCost then C.button else C.buttonDisabled,
					function()
						ui.purchase("Slot")
					end
				)
			else
				ui.row(
					`🐾 Pen Slots {state.slots}/{Config.Plots.maxSlots}`,
					"Your pen is maxed out!",
					C.coins,
					"MAX",
					C.buttonDisabled,
					nil
				)
			end
			ui.note("Tip: faster laps on the Training Track give up to x1.6 bonus Speed. Shoes reset when you rebirth.")
		elseif tab == "Tools" then
			ui.row(
				"🕸 Net Launcher",
				"Knock the egg off a carrier, then grab it",
				C.good,
				"OWNED",
				C.buttonDisabled,
				nil
			)
			if state.tools.Slime then
				ui.row(
					"🟢 Slime Puddle",
					"Slows egg carriers that run through it",
					C.good,
					"OWNED",
					C.buttonDisabled,
					nil
				)
			else
				local cost = Config.Tools.Slime.cost
				ui.row(
					"🟢 Slime Puddle",
					"Slows egg carriers that run through it",
					C.good,
					Format.money(cost),
					if state.coins >= cost then C.button else C.buttonDisabled,
					function()
						ui.purchase("Tool:Slime")
					end
				)
			end
			ui.note("Tools only work on players carrying an egg, so nobody gets bullied for walking around.")
		else
			local now = workspace:GetServerTimeNow()
			ui.note(`You have {state.feathers} 🪶. Earn them from quests, daily rewards, rebirths and heists.`)
			ui.header("✨ Boosts", C.feathers)
			for _, item in Config.FeatherShop do
				local untilTime = if item.id == "Boost:Luck" then state.luckUntil else state.turboUntil
				local active = if untilTime > now then ` • active {Format.clock(untilTime - now)}` else ""
				ui.row(
					`✨ {item.name}`,
					item.desc .. active,
					C.feathers,
					`{item.cost} 🪶`,
					if state.feathers >= item.cost then C.button else C.buttonDisabled,
					function()
						ui.purchase(item.id)
					end
				)
			end
			ui.header("🌈 Trails", C.feathers)
			for _, trail in Config.Trails do
				local owned = state.trails[trail.key] == true
				local equipped = state.equippedTrail == trail.key
				ui.row(
					`🌈 {trail.name}`,
					if equipped then "Equipped" else "A glowing trail behind you",
					trail.c1,
					if equipped then "UNEQUIP" elseif owned then "EQUIP" else `{trail.cost} 🪶`,
					if owned or state.feathers >= trail.cost then C.button else C.buttonDisabled,
					function()
						ui.purchase("Trail:" .. trail.key)
					end
				)
			end
			ui.header("🏡 Nest Themes", C.feathers)
			ui.row(
				"🏡 Classic Nest",
				if state.equippedTheme == "" then "Applied" else "Your nest's original colours",
				C.text,
				if state.equippedTheme == "" then "APPLIED" else "APPLY",
				if state.equippedTheme == "" then C.buttonDisabled else C.button,
				if state.equippedTheme == ""
					then nil
					else function()
						ui.purchase("Theme:Classic")
					end
			)
			for _, theme in Config.Themes do
				local owned = state.themes[theme.key] == true
				local applied = state.equippedTheme == theme.key
				ui.row(
					`🏡 {theme.name}`,
					if applied then "Applied to your nest" else "Repaint your nest's floor and fence",
					theme.rail,
					if applied then "APPLIED" elseif owned then "APPLY" else `{theme.cost} 🪶`,
					if applied
						then C.buttonDisabled
						elseif owned or state.feathers >= theme.cost then C.button
						else C.buttonDisabled,
					if applied
						then nil
						else function()
							ui.purchase("Theme:" .. theme.key)
						end
				)
			end
		end
	end,
}

return Page
