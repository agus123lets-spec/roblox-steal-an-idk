--!strict
-- Global leaderboards: stats go into OrderedDataStores and the top 10 show on the boards in the hub.
-- Needs a published game; in an unpublished Studio test the boards say so.

local DataStoreService: DataStoreService = game:GetService("DataStoreService")
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PlayerService = require(script.Parent.PlayerService)
local Loop = require(script.Parent.Loop)

type Session = PlayerService.Session
type Board = {
	info: Config.BoardInfo,
	store: OrderedDataStore?,
	rows: { { TextLabel } }, -- rows[i] holds that row's label on both faces
	statuses: { TextLabel },
}

local LeaderboardService = {}

local UNPUBLISHED = "Leaderboards appear once the game is published"

local boards: { Board } = {}
local names: { [number]: string } = {}
local lastWritten: { [number]: { [string]: number } } = {}

local function valueFor(key: string, session: Session): number
	local data = session.data
	if key == "Rebirths" then
		return data.rebirths
	elseif key == "Hatched" then
		return data.stats.hatched
	elseif key == "Stolen" then
		return data.stats.stolen
	elseif key == "BestLap" then
		return math.floor(data.stats.bestLap * 1000) -- milliseconds, lowest first
	end
	return 0
end

local function formatValue(info: Config.BoardInfo, value: number): string
	if info.format == "time" then
		return string.format("%.2fs", value / 1000)
	end
	return Format.short(value)
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.Name
		return player.Name
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(result) == "string" then
		names[userId] = result
		return result
	end
	return "Player"
end

local function setStatus(board: Board, text: string)
	for _, label in board.statuses do
		label.Text = text
	end
end

local function setRow(board: Board, index: number, text: string)
	for _, label in board.rows[index] do
		label.Text = text
	end
end

local function loadBoards()
	local map = workspace:FindFirstChild("Map")
	local hub = map and map:FindFirstChild("Hub")
	local folder = hub and hub:FindFirstChild("Leaderboards")
	if not folder then
		warn("[NestHeist] The map has no leaderboards")
		return
	end
	for _, info in Config.Leaderboards.boards do
		local model = folder:FindFirstChild(info.key)
		local part = model and model:FindFirstChild("Board")
		if part then
			local board: Board = { info = info, store = nil, rows = {}, statuses = {} }
			for i = 1, 10 do
				board.rows[i] = {}
			end
			for _, gui in part:GetChildren() do
				if gui:IsA("SurfaceGui") then
					for i = 1, 10 do
						local label = gui:FindFirstChild("Row" .. i)
						if label and label:IsA("TextLabel") then
							table.insert(board.rows[i], label)
						end
					end
					local status = gui:FindFirstChild("Status")
					if status and status:IsA("TextLabel") then
						table.insert(board.statuses, status)
					end
				end
			end
			local ok, store = pcall(function()
				return DataStoreService:GetOrderedDataStore(`{Config.Data.storeName}_LB_{info.key}`)
			end)
			if ok then
				board.store = store
			end
			table.insert(boards, board)
		end
	end
end

local function writeScores(session: Session)
	if not session.persistent then
		return
	end
	local userId = session.player.UserId
	local written = lastWritten[userId] or {}
	lastWritten[userId] = written
	for _, board in boards do
		local store = board.store
		local key = board.info.key
		local value = valueFor(key, session)
		if store and value > 0 and written[key] ~= value then
			local ok = pcall(function()
				store:SetAsync("u_" .. userId, value)
			end)
			if ok then
				written[key] = value
			end
		end
	end
end

local function readBoard(board: Board)
	local store = board.store
	if not store then
		setStatus(board, UNPUBLISHED)
		return
	end
	local ok, entries = pcall(function()
		return store:GetSortedAsync(board.info.ascending, 10):GetCurrentPage()
	end)
	if not ok or type(entries) ~= "table" then
		setStatus(board, UNPUBLISHED)
		return
	end
	for i = 1, 10 do
		local entry = entries[i]
		if type(entry) == "table" and type(entry.key) == "string" and type(entry.value) == "number" then
			local userId = tonumber(string.sub(entry.key, 3)) or 0
			setRow(board, i, `{i}. {nameOf(userId)}  •  {formatValue(board.info, entry.value)}`)
		else
			setRow(board, i, `{i}. ---`)
		end
	end
	setStatus(board, "Global top 10 • updates every few minutes")
end

local function refresh()
	for _, session in PlayerService.all() do
		writeScores(session)
	end
	for _, board in boards do
		readBoard(board)
	end
end

function LeaderboardService.start()
	loadBoards()
	PlayerService.onSessionEnding(function(session: Session)
		-- Ending callbacks must not yield; post the final scores in the background.
		task.spawn(function()
			writeScores(session)
			lastWritten[session.player.UserId] = nil
		end)
	end)
	Loop.every("Leaderboards", Config.Leaderboards.refreshInterval, refresh, 15)
end

return LeaderboardService
