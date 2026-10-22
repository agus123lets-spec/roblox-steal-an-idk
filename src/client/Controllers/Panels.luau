--!strict
-- Menu windows. The pages (Shop, Pets, Rewards, Index, Rebirth) live in Controllers/Pages;
-- this module owns the window, tabs, menu badges and the calls to the server.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UIKit = require(script.Parent.UIKit)
local ClientState = require(script.Parent.ClientState)
local HUD = require(script.Parent.HUD)
local Sounds = require(script.Parent.Sounds)
local Types = require(script.Parent.Pages.Types)
local ShopPage = require(script.Parent.Pages.ShopPage)
local PetsPage = require(script.Parent.Pages.PetsPage)
local RewardsPage = require(script.Parent.Pages.RewardsPage)
local IndexPage = require(script.Parent.Pages.IndexPage)
local RebirthPage = require(script.Parent.Pages.RebirthPage)

local C = UIKit.Colors

type Entry = { name: string, icon: string, color: Color3, page: Types.Page }

local Panels = {}

local MENU: { Entry } = {
	{ name = "Shop", icon = "🛒", color = C.info, page = ShopPage },
	{ name = "Pets", icon = "🐾", color = C.good, page = PetsPage },
	{ name = "Rewards", icon = "🎁", color = C.feathers, page = RewardsPage },
	{ name = "Index", icon = "📖", color = C.warn, page = IndexPage },
	{ name = "Rebirth", icon = "♻️", color = C.rare, page = RebirthPage },
}

local window: Frame
local titleLabel: TextLabel
local tabsBar: Frame
local content: ScrollingFrame
local ui: Types.UI
local current: Entry? = nil
local tabs: { [string]: string } = {}
local tabButtons: { [string]: TextButton } = {}
local badges: { [string]: Frame } = {}
local lastSignature = ""
local rowOrder = 0
local busy = false
local pendingUntil: { [string]: number } = {}

local function nextOrder(): number
	rowOrder += 1
	return rowOrder
end

local function clearContent()
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function row(
	title: string,
	subtitle: string,
	titleColor: Color3?,
	buttonText: string?,
	buttonColor: Color3?,
	onClick: (() -> ())?
): Frame
	local frame = UIKit.frame(content, "Row", UDim2.new(1, -8, 0, 64), UDim2.new(), C.row, 0)
	frame.LayoutOrder = nextOrder()
	UIKit.corner(frame)
	UIKit.stroke(frame, C.stroke, 2)
	local width = if buttonText then -170 else -24
	local titleText =
		UIKit.label(frame, "Title", title, UDim2.new(1, width, 0, 28), UDim2.fromOffset(12, 6), titleColor or C.text)
	titleText.TextXAlignment = Enum.TextXAlignment.Left
	UIKit.textStroke(titleText, 1.5)
	local sub = UIKit.label(
		frame,
		"Subtitle",
		subtitle,
		UDim2.new(1, width, 0, 20),
		UDim2.fromOffset(12, 36),
		C.muted,
		UIKit.BodyFont
	)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	if buttonText then
		local button = UIKit.button(
			frame,
			"Action",
			buttonText,
			UDim2.fromOffset(140, 44),
			UDim2.new(1, -150, 0, 10),
			buttonColor or C.button,
			function()
				if onClick then
					Sounds.play("click")
					onClick()
				end
			end
		)
		button.Active = onClick ~= nil
	end
	return frame
end

local function note(text: string): TextLabel
	local label = UIKit.label(content, "Note", text, UDim2.new(1, -8, 0, 34), UDim2.new(), C.muted, UIKit.BodyFont)
	label.LayoutOrder = nextOrder()
	return label
end

local function header(text: string, color: Color3?): TextLabel
	local label = UIKit.label(content, "Header", text, UDim2.new(1, -8, 0, 32), UDim2.new(), color or C.text)
	label.LayoutOrder = nextOrder()
	UIKit.textStroke(label, 2)
	return label
end

local function run(call: () -> (any, any))
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, result, message = pcall(call)
		busy = false
		if ok then
			HUD.toast(tostring(message), if result then "success" else "warn")
			Sounds.play(if result then "coin" else "error")
		else
			HUD.toast("That didn't work, try again.", "warn")
		end
	end)
end

local function pending(key: string): boolean
	return (pendingUntil[key] or 0) > os.clock()
end

local function confirm(key: string): boolean
	if pending(key) then
		pendingUntil[key] = nil
		return true
	end
	pendingUntil[key] = os.clock() + 3
	Panels.refresh(true)
	task.delay(3.1, function()
		Panels.refresh(true)
	end)
	return false
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function buildTabs(entry: Entry)
	for _, child in tabsBar:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	table.clear(tabButtons)
	local list = entry.page.tabs
	if not list then
		return
	end
	local width = math.floor((588 - 8 * (#list - 1)) / #list)
	for i, name in list do
		local button = UIKit.button(
			tabsBar,
			name,
			name,
			UDim2.fromOffset(math.min(width, 180), 38),
			UDim2.new(),
			C.panelLight,
			function()
				Sounds.play("click")
				tabs[entry.name] = name
				Panels.refresh(true)
			end
		)
		button.LayoutOrder = i
		tabButtons[name] = button
	end
end

function Panels.refresh(force: boolean?)
	local entry = current
	if not entry then
		return
	end
	local page = entry.page
	local state = ClientState.get()
	local tab = tabs[entry.name] or (if page.tabs then page.tabs[1] else "")
	tabs[entry.name] = tab
	local signature = `{entry.name}|{tab}|{page.signature(state, tab)}`
	if not force and signature == lastSignature then
		return
	end
	lastSignature = signature
	local scroll = content.CanvasPosition
	clearContent()
	rowOrder = 0
	local hasTabs = page.tabs ~= nil
	tabsBar.Visible = hasTabs
	content.Position = UDim2.fromOffset(16, if hasTabs then 112 else 66)
	content.Size = UDim2.new(1, -32, 1, if hasTabs then -128 else -82)
	for name, button in tabButtons do
		button.BackgroundColor3 = if name == tab then C.info else C.panelLight
	end
	titleLabel.Text = page.title
	local ok, err = pcall(function(): string?
		page.render(ui, state, tab)
		return nil
	end)
	if not ok then
		warn(`[NestHeist] {entry.name} page error: {err}`)
	end
	-- Keep the scroll position when rows rebuild (after the canvas has grown).
	task.defer(function()
		content.CanvasPosition = scroll
	end)
end

local function open(entry: Entry)
	current = entry
	window.Visible = true
	buildTabs(entry)
	content.CanvasPosition = Vector2.zero
	Panels.refresh(true)
	UIKit.pop(titleLabel, 0.15)
end

local function close()
	current = nil
	window.Visible = false
end

function Panels.toggle(name: string)
	if current and current.name == name then
		close()
		return
	end
	for _, entry in MENU do
		if entry.name == name then
			open(entry)
		end
	end
end

local function makeBadge(button: TextButton): Frame
	local badge = UIKit.frame(button, "Badge", UDim2.fromOffset(24, 24), UDim2.new(1, -14, 0, -8), C.danger)
	badge.ZIndex = 5
	UIKit.corner(badge, UDim.new(1, 0))
	UIKit.stroke(badge, C.stroke, 2)
	local mark = UIKit.label(badge, "Mark", "!", UDim2.fromScale(1, 1), UDim2.new(), C.text)
	mark.ZIndex = 6
	badge.Visible = false
	return badge
end

local function updateBadges()
	local state = ClientState.get()
	local ready = ClientState.hasData()
	for _, entry in MENU do
		local badge = badges[entry.name]
		local check = entry.page.badge
		if badge and check then
			local visible = ready and check(state)
			if badge.Visible ~= visible then
				badge.Visible = visible
				if visible then
					UIKit.pop(badge, 0.4)
				end
			end
		end
	end
end

function Panels.start()
	local gui = HUD.makeScreen("NestHeistPanels", 5)

	window = UIKit.frame(gui, "Window", UDim2.fromOffset(620, 470), UDim2.fromScale(0.5, 0.52), C.panel, 0.02)
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Active = true -- clicks on the window must not fire an equipped tool
	window.Visible = false
	UIKit.corner(window, UDim.new(0, 18))
	UIKit.stroke(window, C.stroke, 4)
	HUD.responsive(window)

	titleLabel = UIKit.label(window, "Title", "", UDim2.new(1, -120, 0, 40), UDim2.fromOffset(20, 12), C.text)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	UIKit.textStroke(titleLabel, 2.5)
	UIKit.button(window, "Close", "X", UDim2.fromOffset(44, 44), UDim2.new(1, -58, 0, 12), C.danger, function()
		Sounds.play("click")
		close()
	end)

	tabsBar = UIKit.frame(window, "Tabs", UDim2.new(1, -32, 0, 40), UDim2.fromOffset(16, 62), C.panel, 1)
	UIKit.list(tabsBar, Enum.FillDirection.Horizontal, 8)

	content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 8
	content.ScrollBarImageColor3 = C.muted
	content.CanvasSize = UDim2.new()
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.Parent = window
	local layout = UIKit.list(content, Enum.FillDirection.Vertical, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	ui = {
		content = content,
		row = row,
		note = note,
		header = header,
		order = nextOrder,
		purchase = function(itemId: string)
			run(function()
				return Remotes.Purchase:InvokeServer(itemId)
			end)
		end,
		sell = function(petId: string)
			run(function()
				return Remotes.SellPet:InvokeServer(petId)
			end)
		end,
		action = function(name: string, arg: any)
			run(function()
				return Remotes.Action:InvokeServer(name, arg)
			end)
		end,
		confirm = confirm,
		pending = pending,
	}

	for i, entry in MENU do
		local button = HUD.addMenuButton(entry.icon, entry.name, entry.color, i, function()
			Sounds.play("click")
			Panels.toggle(entry.name)
		end)
		badges[entry.name] = makeBadge(button)
	end

	ClientState.onChanged(function()
		Panels.refresh()
		updateBadges()
	end)
	-- Countdowns (daily reward, boosts) change without a state push.
	task.spawn(function()
		while true do
			task.wait(1)
			Panels.refresh()
			updateBadges()
		end
	end)
end

return Panels
