--!strict
-- Pets: pen size, fusion (3 of a kind -> the next rarity) and selling.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PetLogic = require(ReplicatedStorage.Shared.PetLogic)
local Progression = require(ReplicatedStorage.Shared.Progression)
local UIKit = require(script.Parent.Parent.UIKit)
local Types = require(script.Parent.Types)

local C = UIKit.Colors

local function sortedPets(pets: { PetLogic.PetData }): { PetLogic.PetData }
	local list = table.clone(pets)
	table.sort(list, function(a, b)
		return PetLogic.income(a) > PetLogic.income(b)
	end)
	return list
end

local function fusable(pets: { PetLogic.PetData }): { string }
	local counts: { [string]: number } = {}
	for _, pet in pets do
		counts[pet.kind] = (counts[pet.kind] or 0) + 1
	end
	local kinds = {}
	for _, info in Config.Pets do
		if (counts[info.key] or 0) >= Config.Fusion.required then
			table.insert(kinds, info.key)
		end
	end
	return kinds
end

local Page: Types.Page = {
	title = "🐾 Your Pets",
	signature = function(state, _tab)
		local ids = {}
		for _, pet in state.pets do
			table.insert(ids, pet.id)
		end
		local slotCost = PetLogic.slotCost(state.slots)
		return `{state.slots}|{slotCost ~= nil and state.coins >= slotCost}|{table.concat(ids, ",")}`
	end,
	render = function(ui, state, _tab)
		local slotCost = PetLogic.slotCost(state.slots)
		ui.row(
			`🐾 {#state.pets}/{state.slots} pets • {Format.money(state.income)}/s`,
			if slotCost then "Buy another slot to earn more" else "Pen maxed out",
			C.coins,
			if slotCost then `+1 slot {Format.money(slotCost)}` else "MAX",
			if slotCost and state.coins >= slotCost then C.button else C.buttonDisabled,
			if slotCost
				then function()
					ui.purchase("Slot")
				end
				else nil
		)
		if #state.pets == 0 then
			ui.note("No pets yet! Grab an egg in 🌼 Meadow Hollow and bring it home.")
			return
		end

		local kinds = fusable(state.pets)
		if #kinds > 0 then
			ui.header("🧪 Fusion: 3 of a kind become 1 stronger pet", C.rare)
			for _, kind in kinds do
				local info = Config.PetByKey[kind]
				local selection = Progression.fuseSelection(state.pets, kind)
				local resultKind, size, mutation =
					if selection then Progression.fuseResult(selection) else nil, "Normal", nil
				if info and resultKind then
					local preview: PetLogic.PetData = { id = "", kind = resultKind, size = size, mutation = mutation }
					local resultInfo = Config.PetByKey[resultKind]
					local key = "fuse:" .. kind
					ui.row(
						`🧪 Fuse 3 {info.name}`,
						`→ {PetLogic.describe(preview)} • {Format.money(PetLogic.income(preview))}/s (uses your weakest)`,
						if resultInfo then Config.Rarities[resultInfo.rarity].color else C.rare,
						if ui.pending(key) then "Sure? Fuse!" else "Fuse",
						if ui.pending(key) then C.danger else C.rare,
						function()
							if ui.confirm(key) then
								ui.action("Fuse", kind)
							end
						end
					)
				end
			end
		end

		ui.header("Your pets", C.text)
		for _, pet in sortedPets(state.pets) do
			local info = Config.PetByKey[pet.kind]
			if info then
				local biome = Config.BiomeByKey[info.biome]
				local key = "sell:" .. pet.id
				ui.row(
					PetLogic.describe(pet),
					`{info.rarity} • {if biome then biome.name else ""} • {Format.money(PetLogic.income(pet))}/s`,
					Config.Rarities[info.rarity].color,
					if ui.pending(key) then "Sure? Sell!" else `Sell {Format.money(PetLogic.sellValue(pet))}`,
					if ui.pending(key) then C.danger else C.warn,
					function()
						if ui.confirm(key) then
							ui.sell(pet.id)
						end
					end
				)
			end
		end
	end,
	badge = function(state)
		return #fusable(state.pets) > 0
	end,
}

return Page
