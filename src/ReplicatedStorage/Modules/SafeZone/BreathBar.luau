--[[
	BreathBar.luau
	--------------
	UI Horror Safe Zone "Breath Meter" — Silencio Carnival Horror.

	Visual:
	  1. Font: `Enum.Font.Creepster` untuk headline status, `SpecialElite` untuk countdown detik.
	  2. Horror Vignette: 4-sisi bayangan hitam/merah darah pekat di sekeliling layar yang
	     berdenyut kencang saat napas kritis.
	  3. Bar Darah & Karat: Bar 20px dengan frame karat tebal, fill gradien merah darah pekat,
	     garis tulang rusuk hitam, dan 20 goresan kuku yang padam satu per detik.
	  4. Panic Shaking: Teks status bergetar saat napas < 25% ("CAN'T HOLD ON!").
	  5. Anti-Nyangkut: State NONE / nil langsung menyembunyikan bar seketika. State penolakan
	     (COOLDOWN/FULL) auto-fade dalam 1.6 detik.
--]]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")

local BreathBar = {}
BreathBar.__index = BreathBar

local GUI_NAME = "SafeZoneBreath"
local MARKS    = 20

local COLOR_BLOOD_BRIGHT = Color3.fromRGB(195, 25, 30)
local COLOR_BLOOD_DARK   = Color3.fromRGB(45, 5, 8)
local COLOR_WARN_GOLD    = Color3.fromRGB(225, 150, 45)
local COLOR_RUST_BG      = Color3.fromRGB(14, 10, 12)
local COLOR_TEXT_LIGHT   = Color3.fromRGB(235, 220, 215)
local COLOR_TEXT_PANIC   = Color3.fromRGB(250, 45, 50)

local TEXT = {
	OCCUPIED = "HOLDING BREATH",
	BREACHED = "IT HEARD YOU!",
	COOLDOWN = "STALL IS COMPROMISED",
	READY    = "HIDDEN IN SHADOWS",
	FULL     = "STALL IS OCCUPIED",
}

local STRAIN = {
	warn  = "LUNGS BURNING...",
	panic = "CAN'T HOLD ON!",
}

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

function BreathBar.new()
	local self = setmetatable({}, BreathBar)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screen = playerGui:FindFirstChild(GUI_NAME) or new("ScreenGui", {
		Name = GUI_NAME,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 15,
		Parent = playerGui,
	})
	screen:ClearAllChildren()

	-- 1. Horror Vignette: 4-sisi bayangan gelap/merah pekat tanpa dependensi asset id
	local vignetteContainer = new("Frame", {
		Name = "HorrorVignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Active = false,
		Parent = screen,
	})

	local topVig = new("Frame", {
		Size = UDim2.new(1, 0, 0.35, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(25, 0, 4),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = vignetteContainer,
	})
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1)
		}),
		Parent = topVig,
	})

	local bottomVig = new("Frame", {
		Size = UDim2.new(1, 0, 0.45, 0),
		Position = UDim2.new(0, 0, 0.55, 0),
		BackgroundColor3 = Color3.fromRGB(30, 0, 5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = vignetteContainer,
	})
	new("UIGradient", {
		Rotation = -90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1)
		}),
		Parent = bottomVig,
	})

	local leftVig = new("Frame", {
		Size = UDim2.new(0.3, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(20, 0, 3),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = vignetteContainer,
	})
	new("UIGradient", {
		Rotation = 0,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1)
		}),
		Parent = leftVig,
	})

	local rightVig = new("Frame", {
		Size = UDim2.new(0.3, 0, 1, 0),
		Position = UDim2.new(0.7, 0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(20, 0, 3),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = vignetteContainer,
	})
	new("UIGradient", {
		Rotation = 180,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1)
		}),
		Parent = rightVig,
	})

	-- 2. HUD Container
	local holder = new("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -60),
		Size = UDim2.new(0.34, 0, 0, 84),
		BackgroundTransparency = 1,
		Active = false,
		Visible = false,
		Parent = screen,
	})

	-- 3. Label Status Seram (Font Creepster)
	local label = new("TextLabel", {
		Name = "StatusLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.Creepster,
		TextSize = 28,
		TextColor3 = COLOR_TEXT_LIGHT,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0,
		Text = "HOLDING BREATH",
		Active = false,
		Parent = holder,
	})

	-- 4. Countdown Angka (Font SpecialElite)
	local countdown = new("TextLabel", {
		Name = "Countdown",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -2, 1, -28),
		Size = UDim2.new(0, 60, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.SpecialElite,
		TextSize = 18,
		TextColor3 = COLOR_WARN_GOLD,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.1,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "20s",
		Active = false,
		Parent = holder,
	})

	-- 5. Deretan 20 Goresan Kuku (Scratches)
	local scratches = new("Frame", {
		Name = "Scratches",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 2, 1, -30),
		Size = UDim2.new(1, -68, 0, 12),
		BackgroundTransparency = 1,
		Active = false,
		Parent = holder,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 2),
		Parent = scratches,
	})

	local marks = table.create(MARKS)
	for i = 1, MARKS do
		marks[i] = new("Frame", {
			Name = "Mark" .. i,
			Size = UDim2.new(0, 3, 0, (i % 2 == 0) and 11 or 7),
			BackgroundColor3 = Color3.fromRGB(170, 150, 140),
			BorderSizePixel = 0,
			Rotation = ((i * 7) % 15) - 7,
			LayoutOrder = i,
			Active = false,
			Parent = scratches,
		})
	end

	-- 6. Frame Bar Luar
	local track = new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundColor3 = COLOR_RUST_BG,
		BorderSizePixel = 0,
		Active = false,
		Parent = holder,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = track })
	new("UIStroke", {
		Color = Color3.fromRGB(80, 12, 18),
		Thickness = 1.8,
		Transparency = 0.15,
		Parent = track,
	})

	-- 7. Isi Bar Darah (Fill)
	local fill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Active = false,
		Parent = track,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 3), Parent = fill })

	local bloodGradient = new("UIGradient", {
		Color = ColorSequence.new(COLOR_BLOOD_BRIGHT, COLOR_BLOOD_DARK),
		Rotation = 90,
		Parent = fill,
	})

	-- 8. Garis Tulang Rusuk
	local ribs = new("Frame", {
		Name = "Ribs",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Active = false,
		Parent = track,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 11),
		Parent = ribs,
	})
	for i = 1, 30 do
		new("Frame", {
			Size = UDim2.new(0, 1.5, 1, 0),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			Active = false,
			Parent = ribs,
		})
	end

	self.screen = screen
	self.vignetteContainer = vignetteContainer
	self.vigFrames = { topVig, bottomVig, leftVig, rightVig }
	self.holder = holder
	self.label = label
	self.countdown = countdown
	self.track = track
	self.fill = fill
	self.marks = marks
	self.bloodGradient = bloodGradient
	self.autoHideToken = 0
	self.pulseTween = nil
	self.jitterConn = nil

	return self
end

function BreathBar:_setVignetteAlpha(targetTransparency: number, duration: number)
	for _, f in self.vigFrames do
		TweenService:Create(f, TweenInfo.new(duration or 0.4), {
			BackgroundTransparency = targetTransparency
		}):Play()
	end
end

function BreathBar:_startVignettePulse(speed: number, maxAlpha: number)
	if self.pulseTween then
		self.pulseTween:Cancel()
		self.pulseTween = nil
	end

	for _, f in self.vigFrames do
		self.pulseTween = TweenService:Create(
			f,
			TweenInfo.new(speed, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ BackgroundTransparency = maxAlpha }
		)
		self.pulseTween:Play()
	end
end

function BreathBar:_stopVignette()
	if self.pulseTween then
		self.pulseTween:Cancel()
		self.pulseTween = nil
	end
	self:_setVignetteAlpha(1, 0.35)
end

function BreathBar:_setJitter(enabled: boolean)
	if enabled and not self.jitterConn then
		self.jitterConn = RunService.RenderStepped:Connect(function()
			if self.label and self.label.Parent then
				local ox = (math.random() - 0.5) * 3
				local oy = (math.random() - 0.5) * 2
				self.label.Position = UDim2.new(0.5, ox, 0, oy)
			end
		end)
	elseif not enabled and self.jitterConn then
		self.jitterConn:Disconnect()
		self.jitterConn = nil
		if self.label then
			self.label.Position = UDim2.new(0.5, 0, 0, 0)
		end
	end
end

function BreathBar:update(payload: { [string]: any }?)
	if not self.holder or not self.holder.Parent then
		return
	end

	-- State NONE / nil -> Hancurkan tampilan seketika (Anti-Nyangkut)
	if not payload or payload.state == nil or payload.state == "NONE" then
		self.autoHideToken += 1
		self:_stopVignette()
		self:_setJitter(false)
		TweenService:Create(self.holder, TweenInfo.new(0.2), { Position = UDim2.new(0.5, 0, 1, -30) }):Play()
		task.delay(0.2, function()
			if self.holder then
				self.holder.Visible = false
				self.holder.Position = UDim2.new(0.5, 0, 1, -60)
			end
		end)
		return
	end

	local state = tostring(payload.state)
	local fraction = math.clamp(tonumber(payload.fraction) or 0, 0, 1)
	local breathSec = math.max(0, math.floor((tonumber(payload.breath) or 0) + 0.5))

	local labelText = TEXT[state] or state
	local labelColor = COLOR_TEXT_LIGHT

	if state == "OCCUPIED" then
		if fraction <= 0.25 then
			labelText = STRAIN.panic
			labelColor = COLOR_TEXT_PANIC
			self:_startVignettePulse(0.4, 0.2) -- Denyut merah cepat saat napas kritis
			self:_setJitter(true)             -- Teks bergetar panik
		elseif fraction <= 0.55 then
			labelText = STRAIN.warn
			labelColor = COLOR_WARN_GOLD
			self:_startVignettePulse(0.9, 0.5) -- Denyut sedang
			self:_setJitter(false)
		else
			labelText = TEXT.OCCUPIED
			labelColor = COLOR_TEXT_LIGHT
			self:_setVignetteAlpha(0.65, 0.5) -- Gelap samar di tepi
			self:_setJitter(false)
		end
		self.countdown.Text = string.format("%ds", breathSec)
		self.countdown.Visible = true
	else
		-- State BREACHED / COOLDOWN / FULL
		self.countdown.Visible = false
		labelColor = COLOR_TEXT_PANIC
		self:_stopVignette()
		self:_setJitter(false)

		-- AUTO-HIDE ANTI-NYANGKUT: Penolakan atau bilik spent auto-fade dalam 1.6s
		self.autoHideToken += 1
		local currentToken = self.autoHideToken
		task.delay(1.6, function()
			if self.autoHideToken == currentToken and self.holder then
				self:update(nil)
			end
		end)
	end

	self.label.Text = labelText
	self.label.TextColor3 = labelColor

	-- Tween Fill Bar
	TweenService:Create(
		self.fill,
		TweenInfo.new(0.12, Enum.EasingStyle.Linear),
		{ Size = UDim2.fromScale(fraction, 1) }
	):Play()

	-- Tally Marks (Goresan Kuku)
	local litCount = math.ceil(fraction * MARKS)
	for i, mark in self.marks do
		if i <= litCount then
			mark.BackgroundColor3 = Color3.fromRGB(170, 150, 140)
			mark.BackgroundTransparency = 0.15
		else
			mark.BackgroundColor3 = Color3.fromRGB(35, 6, 10)
			mark.BackgroundTransparency = 0.85
		end
	end

	self.holder.Visible = true
end

function BreathBar:destroy()
	self:_stopVignette()
	self:_setJitter(false)
	if self.screen then
		self.screen:Destroy()
	end
	self.screen = nil
	self.holder = nil
	self.label = nil
	self.countdown = nil
	self.vignetteContainer = nil
	self.vigFrames = nil
	self.marks = nil
end

return BreathBar
