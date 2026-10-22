--!strict
-- Shared types for the menu pages. Panels builds the UI helpers; each page only describes its rows.

local ClientState = require(script.Parent.Parent.ClientState)

export type UI = {
	content: ScrollingFrame,
	-- A rounded row with a title, subtitle and an optional button.
	row: (
		title: string,
		subtitle: string,
		titleColor: Color3?,
		buttonText: string?,
		buttonColor: Color3?,
		onClick: (() -> ())?
	) -> Frame,
	note: (text: string) -> TextLabel,
	header: (text: string, color: Color3?) -> TextLabel,
	order: () -> number, -- LayoutOrder for custom elements
	purchase: (itemId: string) -> (),
	sell: (petId: string) -> (),
	action: (name: string, arg: any) -> (),
	-- Two-tap confirmation: the first call arms it (returns false), a second within 3s returns true.
	confirm: (key: string) -> boolean,
	pending: (key: string) -> boolean,
}

export type Page = {
	title: string,
	tabs: { string }?,
	-- Rows rebuild only when this changes, so frequent coin updates don't eat clicks.
	signature: (state: ClientState.State, tab: string) -> string,
	render: (ui: UI, state: ClientState.State, tab: string) -> (),
	-- Shows a "!" on the menu button.
	badge: ((state: ClientState.State) -> boolean)?,
}

return {}
