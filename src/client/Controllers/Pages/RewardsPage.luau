--!strict
-- Rewards: daily login streak, daily quests and codes.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Progression = require(ReplicatedStorage.Shared.Progression)
local UIKit = require(script.Parent.Parent.UIKit)
local ClientState = require(script.Parent.Parent.ClientState)
local Types = require(script.Parent.Types)

local C = UIKit.Colors

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rewardIcon(reward: Config.DailyReward): string
	local parts = {}
	if reward.feathers then
		table.insert(parts, `🪶{reward.feathers}`)
	end
	if reward.coinsSeconds then
		table.insert(parts, "💰")
	end
	if reward.boost == "Luck" then
		table.insert(parts, `🍀{reward.minutes or 10}m`)
	elseif reward.boost == "Turbo" then
		table.insert(parts, `👟{reward.minutes or 10}m`)
	end
	return table.concat(parts, " ")
end

local function questsReady(state: ClientState.State): boolean
	local list = state.quests.list
	local allClaimed = #list > 0
	for _, quest in list do
		if not quest.claimed then
			allClaimed = false
			if quest.progress >= quest.target then
				return true
			end
		end
	end
	return allClaimed and not state.quests.bonusClaimed
end

local function renderDaily(ui: Types.UI, state: ClientState.State)
	local t = now()
	local daily = state.daily
	local canClaim = Progression.canClaimDaily(daily.last, t)
	local streak = if canClaim then Progression.nextStreak(daily.last, daily.streak, t) else math.max(daily.streak, 1)
	local cycle = #Config.Daily.rewards
	local today = (streak - 1) % cycle + 1

	local strip = UIKit.frame(ui.content, "Days", UDim2.new(1, -8, 0, 100), UDim2.new(), C.panel, 1)
	strip.LayoutOrder = ui.order()
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(74, 96)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = strip
	for day, reward in Config.Daily.rewards do
		local claimed = day < today or (day == today and not canClaim)
		local isToday = day == today
		local tile = UIKit.frame(
			strip,
			"Day" .. day,
			UDim2.fromOffset(74, 96),
			UDim2.new(),
			if isToday then C.panelLight else C.row
		)
		tile.LayoutOrder = day
		UIKit.corner(tile)
		UIKit.stroke(tile, if isToday then C.coins else C.stroke, if isToday then 3 else 2)
		UIKit.label(
			tile,
			"Day",
			`Day {day}`,
			UDim2.new(1, -8, 0, 22),
			UDim2.fromOffset(4, 4),
			if isToday then C.coins else C.muted
		)
		local icon =
			UIKit.label(tile, "Reward", rewardIcon(reward), UDim2.new(1, -8, 0, 40), UDim2.fromOffset(4, 28), C.text)
		UIKit.textStroke(icon, 1.5)
		UIKit.label(
			tile,
			"State",
			if claimed then "✅" elseif isToday then "TODAY" else "",
			UDim2.new(1, -8, 0, 20),
			UDim2.fromOffset(4, 70),
			C.good
		)
	end

	if canClaim then
		ui.row("🎁 Daily reward ready!", `Day {streak} of your streak`, C.coins, "Claim!", C.button, function()
			ui.action("ClaimDaily", nil)
		end)
	else
		local wait = Progression.nextDailyAt(daily.last) - t
		ui.row(
			"🎁 Come back later",
			`Next reward in {Format.duration(wait)} • streak {daily.streak}`,
			C.muted,
			"Waiting",
			C.buttonDisabled,
			nil
		)
	end
	ui.note("Claim every day to grow your streak. Miss two days and it starts over.")
end

local function renderQuests(ui: Types.UI, state: ClientState.State)
	local t = now()
	local quests = state.quests
	if quests.day ~= Progression.questDay(t) or #quests.list == 0 then
		ui.note("New quests are on the way...")
		return
	end
	local allClaimed = true
	for index, quest in quests.list do
		local done = quest.progress >= quest.target
		allClaimed = allClaimed and quest.claimed
		ui.row(
			`📜 {Progression.questText(quest.id, quest.target)}`,
			`{quest.progress}/{quest.target} • +{quest.feathers} 🪶`,
			if done then C.good else C.text,
			if quest.claimed then "Done ✓" elseif done then "Claim!" else `{quest.progress}/{quest.target}`,
			if done and not quest.claimed then C.button else C.buttonDisabled,
			if done and not quest.claimed
				then function()
					ui.action("ClaimQuest", index)
				end
				else nil
		)
	end
	local q = Config.Quests
	ui.row(
		"🏆 Daily bonus",
		`Finish all quests: +{q.bonusFeathers} 🪶 and {q.bonusLuckMinutes} min Lucky Charm`,
		C.coins,
		if quests.bonusClaimed then "Done ✓" elseif allClaimed then "Claim!" else "Locked",
		if allClaimed and not quests.bonusClaimed then C.button else C.buttonDisabled,
		if allClaimed and not quests.bonusClaimed
			then function()
				ui.action("ClaimQuest", "bonus")
			end
			else nil
	)
	local nextDay = (Progression.questDay(t) + 1) * 86400
	ui.note(`New quests in {Format.duration(nextDay - t)}`)
end

local function renderCodes(ui: Types.UI, state: ClientState.State)
	ui.note("Got a code? Type it below. New codes come with updates!")
	local frame = UIKit.frame(ui.content, "CodeRow", UDim2.new(1, -8, 0, 64), UDim2.new(), C.row, 0)
	frame.LayoutOrder = ui.order()
	UIKit.corner(frame)
	UIKit.stroke(frame, C.stroke, 2)
	local box = Instance.new("TextBox")
	box.Name = "CodeBox"
	box.Size = UDim2.new(1, -170, 0, 44)
	box.Position = UDim2.fromOffset(12, 10)
	box.BackgroundColor3 = C.panel
	box.TextColor3 = C.text
	box.PlaceholderText = "Enter code"
	box.PlaceholderColor3 = C.muted
	box.Text = ""
	box.ClearTextOnFocus = false
	box.FontFace = Font.fromEnum(UIKit.Font)
	box.TextScaled = true
	box.Parent = frame
	UIKit.corner(box)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 26
	limit.Parent = box
	UIKit.button(frame, "Redeem", "Redeem", UDim2.fromOffset(140, 44), UDim2.new(1, -150, 0, 10), C.button, function()
		ui.action("Redeem", box.Text)
	end)
	local count = 0
	for _ in state.codes do
		count += 1
	end
	ui.note(
		if count > 0
			then `You've redeemed {count} code{if count == 1 then "" else "s"}.`
			else "Try NESTHEIST to get started!"
	)
end

local Page: Types.Page = {
	title = "🎁 Rewards",
	tabs = { "Daily", "Quests", "Codes" },
	signature = function(state, tab)
		local t = now()
		if tab == "Daily" then
			return `{state.daily.last}|{state.daily.streak}|{Progression.canClaimDaily(state.daily.last, t)}|{math.floor(
				t / 30
			)}`
		elseif tab == "Quests" then
			local parts =
				{ tostring(state.quests.day), tostring(state.quests.bonusClaimed), tostring(math.floor(t / 60)) }
			for _, quest in state.quests.list do
				table.insert(parts, `{quest.id}{quest.progress}{quest.claimed}`)
			end
			return table.concat(parts, "|")
		end
		-- Codes: only rebuild after a redeem, so typing isn't interrupted.
		local count = 0
		for _ in state.codes do
			count += 1
		end
		return tostring(count)
	end,
	render = function(ui, state, tab)
		if tab == "Daily" then
			renderDaily(ui, state)
		elseif tab == "Quests" then
			renderQuests(ui, state)
		else
			renderCodes(ui, state)
		end
	end,
	badge = function(state)
		return Progression.canClaimDaily(state.daily.last, now()) or questsReady(state)
	end,
}

return Page
