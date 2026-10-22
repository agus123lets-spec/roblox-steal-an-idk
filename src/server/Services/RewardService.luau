--!strict
-- Daily login rewards (with streaks), daily quests and redeemable codes.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Format = require(ReplicatedStorage.Shared.Format)
local PlayerService = require(script.Parent.PlayerService)
local Actions = require(script.Parent.Actions)
local Loop = require(script.Parent.Loop)

type Session = PlayerService.Session

local RewardService = {}

-- New quests at midnight UTC; old progress is dropped.
function RewardService.ensureQuests(session: Session)
	local day = Progression.questDay(os.time())
	if session.data.quests.day ~= day then
		session.data.quests = {
			day = day,
			list = Progression.generateQuests(session.player.UserId, day),
			bonusClaimed = false,
		}
		session.dirty = true
	end
end

-- Quest hooks call this from gameplay (hatching, laps, steals, ...).
function RewardService.progress(session: Session, id: string, amount: number?)
	if session.ended then
		return
	end
	RewardService.ensureQuests(session)
	for _, quest in session.data.quests.list do
		if quest.id == id and quest.progress < quest.target then
			quest.progress = math.min(quest.target, quest.progress + (amount or 1))
			session.dirty = true
			if quest.progress >= quest.target then
				PlayerService.notify(
					session.player,
					`✅ Quest done: {Progression.questText(quest.id, quest.target)}! Claim it in 🎁 Rewards.`,
					"success"
				)
			end
		end
	end
end

local function grantBoost(session: Session, kind: string, minutes: number)
	local now = PlayerService.now()
	if kind == "Luck" then
		session.luckUntil = math.max(session.luckUntil, now) + minutes * 60
	else
		session.turboUntil = math.max(session.turboUntil, now) + minutes * 60
	end
	session.dirty = true
end

local function boostName(kind: string): string
	return if kind == "Luck" then "Lucky Charm" else "Turbo Laces"
end

local function claimDaily(session: Session, _arg: any): (boolean, string)
	local daily = session.data.daily
	local now = os.time()
	if not Progression.canClaimDaily(daily.last, now) then
		return false, `Your next daily reward is ready in {Format.duration(Progression.nextDailyAt(daily.last) - now)}.`
	end
	local streak = Progression.nextStreak(daily.last, daily.streak, now)
	local reward = Progression.dailyReward(streak)
	daily.last = now
	daily.streak = streak
	local parts = {}
	local coins = Progression.dailyCoins(reward, session.income)
	if coins > 0 then
		PlayerService.addCoins(session, coins)
		table.insert(parts, Format.money(coins))
	end
	if reward.feathers then
		PlayerService.addFeathers(session, reward.feathers)
		table.insert(parts, `{reward.feathers} 🪶`)
	end
	if reward.boost then
		local minutes = reward.minutes or 10
		grantBoost(session, reward.boost, minutes)
		table.insert(parts, `{minutes} min {boostName(reward.boost)}`)
	end
	return true, `🎁 Day {streak} reward: {table.concat(parts, " + ")}!`
end

local function claimQuest(session: Session, arg: any): (boolean, string)
	RewardService.ensureQuests(session)
	local quests = session.data.quests
	if arg == "bonus" then
		if quests.bonusClaimed then
			return false, "You already claimed today's bonus."
		end
		for _, quest in quests.list do
			if not quest.claimed then
				return false, "Claim all of today's quests first!"
			end
		end
		quests.bonusClaimed = true
		local q = Config.Quests
		PlayerService.addFeathers(session, q.bonusFeathers)
		grantBoost(session, "Luck", q.bonusLuckMinutes)
		return true, `🏆 All quests done! +{q.bonusFeathers} 🪶 and {q.bonusLuckMinutes} min Lucky Charm`
	end
	local index = if type(arg) == "number" then arg else nil
	local quest = if index then quests.list[index] else nil
	if not quest then
		return false, "That quest doesn't exist anymore."
	end
	if quest.claimed then
		return false, "Already claimed."
	end
	if quest.progress < quest.target then
		return false, "Finish the quest first!"
	end
	quest.claimed = true
	PlayerService.addFeathers(session, quest.feathers)
	return true, `✅ Quest reward: +{quest.feathers} 🪶`
end

local function redeem(session: Session, arg: any): (boolean, string)
	if type(arg) ~= "string" or #arg == 0 or #arg > 40 then
		return false, "Type a code first."
	end
	local code = Progression.normalizeCode(arg)
	local info = Config.Codes[code]
	if not info then
		return false, "That code doesn't exist (or it expired)."
	end
	if session.data.codes[code] then
		return false, "You already redeemed that code."
	end
	session.data.codes[code] = true
	local parts = {}
	if info.coins then
		PlayerService.addCoins(session, info.coins)
		table.insert(parts, Format.money(info.coins))
	end
	if info.feathers then
		PlayerService.addFeathers(session, info.feathers)
		table.insert(parts, `{info.feathers} 🪶`)
	end
	if info.luckMinutes then
		grantBoost(session, "Luck", info.luckMinutes)
		table.insert(parts, `{info.luckMinutes} min Lucky Charm`)
	end
	if info.turboMinutes then
		grantBoost(session, "Turbo", info.turboMinutes)
		table.insert(parts, `{info.turboMinutes} min Turbo Laces`)
	end
	return true, `🎟 Code redeemed: {table.concat(parts, " + ")}!`
end

function RewardService.start()
	Actions.register("ClaimDaily", claimDaily)
	Actions.register("ClaimQuest", claimQuest)
	Actions.register("Redeem", redeem)

	PlayerService.onSessionStarted(function(session: Session)
		RewardService.ensureQuests(session)
		if Progression.canClaimDaily(session.data.daily.last, os.time()) then
			task.delay(6, function()
				PlayerService.notify(
					session.player,
					"🎁 Your daily reward is ready! Open 🎁 Rewards to claim it.",
					"rare"
				)
			end)
		end
	end)

	Loop.every("Quests", 60, function()
		for _, session in PlayerService.all() do
			RewardService.ensureQuests(session)
		end
	end)
end

return RewardService
