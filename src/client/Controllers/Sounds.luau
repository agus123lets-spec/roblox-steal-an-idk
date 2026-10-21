--!strict
-- Local sound effects. Uses Roblox's built-in classic sounds so no audio upload is needed;
-- swap any id for your own Creator Store audio if you like.

local SoundService: SoundService = game:GetService("SoundService")

local Sounds = {}

local IDS: { [string]: string } = {
	click = "rbxasset://sounds/button.mp3",
	coin = "rbxasset://sounds/electronicpingshort.mp3",
	grab = "rbxasset://sounds/snap.mp3",
	deposit = "rbxasset://sounds/clickfast.mp3",
	dash = "rbxasset://sounds/swoosh.mp3",
	net = "rbxasset://sounds/Rubber band sling shot.mp3",
	slime = "rbxasset://sounds/splat.mp3",
	hatch = "rbxasset://sounds/victory.mp3",
	alarm = "rbxasset://sounds/switch.mp3",
	caught = "rbxasset://sounds/Kerplunk.mp3",
	jackpot = "rbxasset://sounds/flashbulb.mp3",
	lap = "rbxasset://sounds/electronicpingshort.mp3",
	error = "rbxasset://sounds/collide.mp3",
}

local VOLUMES: { [string]: number } = {
	click = 0.4,
	coin = 0.35,
	hatch = 0.6,
	alarm = 0.6,
	jackpot = 0.6,
}

local cache: { [string]: Sound } = {}

function Sounds.play(name: string, pitch: number?)
	local id = IDS[name]
	if not id then
		return
	end
	local sound = cache[name]
	if not sound then
		local created = Instance.new("Sound")
		created.Name = "NestHeist_" .. name
		created.SoundId = id
		created.Volume = VOLUMES[name] or 0.5
		created.Parent = SoundService
		cache[name] = created
		sound = created
	end
	sound.PlaybackSpeed = pitch or 1
	SoundService:PlayLocalSound(sound)
end

return Sounds
