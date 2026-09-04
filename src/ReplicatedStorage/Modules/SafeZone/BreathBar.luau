--[[
	BreathBar.luau
	--------------
	Safe Zone breath meter — "Choked Breath" design.

	The bar is not a progress meter, it is a pair of lungs: it GASPS instead of
	draining smoothly, the fill is dark clotted blood rather than a clean tint,
	and the 20 tally marks above it are fingernail scratches on the stall wall —
	one per second, each one going dark as it burns away.

	SWAPPABLE MODULE. If the team ships their own design, replace this file (or
	drop a new module in this folder and point `UI_MODULE` in `SafeZoneUI` at
	it). Nothing else needs to change.

	CONTRACT
	  BreathBar.new()       -> bar object
	  bar:update(payload)   -> payload from RemoteEvent "SafeZoneState"
	                           (nil / state "NONE" hides the bar)
	  bar:destroy()         -> release every instance and connection

	Pure presentation — zero game logic. The server owns the truth; this only
	draws what it is told.
--]]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local BreathBar = {}
BreathBar.__index = BreathBar

local GUI_NAME = "SafeZoneBreath"
local MARKS    = 20      -- one scratch per second of a default 20s breath

-- Layout
local WIDTH, HEIGHT, BOTTOM = 0.28, 14, 90

-- Blood darkens toward the top edge; brightens as panic sets in.
local BLOOD = {
	calm  = { Color3.fromRGB(125, 20, 24), Color3.fromRGB(43,  10, 13) },
	warn  = { Color3.fromRGB(141, 26, 30), Color3.fromRGB(44,   6,  8) },
	panic = { Color3.fromRGB(165, 31, 34), Color3.fromRGB(48,   7,  9) },
}
local INK = {                                    -- label colour
	calm   = Color3.fromRGB(141, 124, 120),
	warn   = Color3.fromRGB(160, 134, 129),
	panic  = Color3.fromRGB(194, 154, 148),
	breach = Color3.fromRGB(142,  20,  24),
}
local GASP = { calm = 3.4, warn = 2.1, panic = 1.0 }   -- seconds per breath
local SCRATCH_LIT  = Color3.fromRGB(110,  95,  91)
local SCRATCH_GONE = Color3.fromRGB( 42,  17,  20)

local TEXT = {
	OCCUPIED = "holding breath",
	BREACHED = "it heard you",
	COOLDOWN = "the stall is spent",
	READY    = "stall is clear",
	FULL     = "someone is inside",
}
-- OCCUPIED reads differently as the air runs out.
local STRAIN = { warn = "lungs burning", panic = "can't hold on" }

local WARN_AT, PANIC_AT = 0.55, 0.25

---------------------------------------------------------------------
-- BUILD
---------------------------------------------------------------------

local function new(class: string, props: { [string]: any }): any
	local inst = Instance.new(class)
	local parent = props.Parent
	props.Parent = nil
	for key, value in props do
		(inst :: any)[key] = value
	end
	inst.Parent = parent
	return inst
end

--- Vertical two-stop gradient (top .. bottom).
local function gradient(parent: Instance, top: Color3, bottom: Color3): UIGradient
	return new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(top, bottom),
		Parent = parent,
	})
end

function BreathBar.new()
	local self = setmetatable({}, BreathBar)
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- ResetOnSpawn = false: the bar has to survive respawn, same as
	-- DamageEffect's vignette, or it silently stops working after one death.
	local screen = gui:FindFirstChild(GUI_NAME) or new("ScreenGui", {
		Name = GUI_NAME,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 6,
		Parent = gui,
	})
	screen:ClearAllChildren()

	-- Active = false everywhere: the HUD must never eat the player's clicks.
	local holder = new("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -BOTTOM),
		Size = UDim2.new(WIDTH, 0, 0, HEIGHT + 40),
		BackgroundTransparency = 1,
		Active = false,
		Visible = false,
		Parent = screen,
	})

	local label = new("TextLabel", {
		Name = "Label",
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.Garamond,
		TextSize = 18,
		TextColor3 = INK.calm,
		TextStrokeTransparency = 0.55,
		Text = "",
		Active = false,
		Parent = holder,
	})

	-- Scratches sit just above the bar: 20 tally marks, slightly crooked.
	local scratches = new("Frame", {
		Name = "Scratches",
		Position = UDim2.new(0, 0, 0, 18),
		Size = UDim2.new(1, 0, 0, 11),
		BackgroundTransparency = 1,
		Active = false,
		Parent = holder,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, 3),
		Parent = scratches,
	})

	self.marks = table.create(MARKS)
	for i = 1, MARKS do
		self.marks[i] = new("Frame", {
			Name = "M" .. i,
			Size = UDim2.new(0, 2, 1, 0),
			BackgroundColor3 = SCRATCH_LIT,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			Rotation = (i % 3) - 1,          -- crooked, not a tidy grid
			LayoutOrder = i,
			Active = false,
			Parent = scratches,
		})
	end

	local track = new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, HEIGHT),
		BackgroundColor3 = Color3.fromRGB(20, 20, 24),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Active = false,
		Parent = holder,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = track })

	local fill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Active = false,
		Parent = track,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = fill })

	-- Rib bars laid over the fill so the blood reads as caged, not as a tube.
	local ribs = new("Frame", {
		Name = "Ribs",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Active = false,
		Parent = track,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 13),
		Parent = ribs,
	})
	for i = 1, 24 do
		new("Frame", {
			Size = UDim2.new(0, 2, 1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Active = false,
			Parent = ribs,
		})
	end

	self.screen, self.holder, self.label = screen, holder, label
	self.track, self.fill = track, fill
	self.blood = gradient(fill, BLOOD.calm[1], BLOOD.calm[2])
	self.tone, self.gasp = nil, nil
	self.visible = false

	return self
end

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------

local function toneFor(fraction: number): string
	return fraction <= PANIC_AT and "panic"
		or fraction <= WARN_AT and "warn"
		or "calm"
end

--- Gasping: the bar swells and collapses instead of sitting still. Faster as
--- the air runs out, which is the cue players read before the number.
function BreathBar:_breathe(tone: string)
	if self.tone == tone then
		return
	end
	self.tone = tone

	if self.gasp then
		self.gasp:Cancel()
		self.gasp = nil
	end
	self.track.Size = UDim2.new(1, 0, 0, HEIGHT)

	local period = GASP[tone]
	if not period then                     -- breach: the lungs stop
		return
	end

	self.gasp = TweenService:Create(
		self.track,
		TweenInfo.new(period / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Size = UDim2.new(1, 0, 0, HEIGHT + 7) }
	)
	self.gasp:Play()
end

function BreathBar:_show(visible: boolean)
	self.visible = visible
	self.holder.Visible = visible
end

--- Draw the latest state.
--- @param payload  table from the RemoteEvent, or nil to hide
function BreathBar:update(payload: { [string]: any }?)
	if not self.holder or not self.holder.Parent then
		return
	end

	if not payload or payload.state == nil or payload.state == "NONE" then
		self:_show(false)
		return
	end

	local state = tostring(payload.state)

	-- An eternal stall has no timer, so a meter would be a lie.
	if payload.eternal == true then
		self.label.Text = "safe"
		self.label.TextColor3 = INK.calm
		self.fill.Size = UDim2.fromScale(1, 1)
		self:_breathe("calm")
		self:_show(true)
		return
	end

	local fraction = math.clamp(tonumber(payload.fraction) or 0, 0, 1)
	local breached = state == "BREACHED" or fraction <= 0
	local tone = breached and "breach" or toneFor(fraction)

	local text = TEXT[state] or state
	if state == "OCCUPIED" then
		text = STRAIN[tone] or text
		local left = math.max(0, math.floor((tonumber(payload.breath) or 0) + 0.5))
		text = string.format("%s  %ds", text, left)
	end

	self.label.Text = text
	self.label.TextColor3 = INK[tone] or INK.calm

	local blood = BLOOD[tone] or BLOOD.panic
	self.blood.Color = ColorSequence.new(blood[1], blood[2])

	-- Short tween so the bar does not jerk between 0.1s server ticks.
	TweenService:Create(
		self.fill,
		TweenInfo.new(0.12, Enum.EasingStyle.Linear),
		{ Size = UDim2.fromScale(fraction, 1) }
	):Play()

	-- Scratches burn away one per second, counting down from the right.
	local lit = math.ceil(fraction * MARKS)
	for i, mark in self.marks do
		local gone = i > lit
		mark.BackgroundColor3 = gone and SCRATCH_GONE or SCRATCH_LIT
		mark.BackgroundTransparency = gone and 0.05 or 0.5
		mark.Size = UDim2.new(0, 2, gone and 0.6 or 1, 0)
	end

	self:_breathe(tone)
	self:_show(true)
end

function BreathBar:destroy()
	if self.gasp then
		self.gasp:Cancel()
	end
	if self.screen then
		self.screen:Destroy()
	end
	self.screen, self.holder, self.label = nil, nil, nil
	self.track, self.fill, self.blood, self.gasp = nil, nil, nil, nil
	self.marks = nil
end

return BreathBar
