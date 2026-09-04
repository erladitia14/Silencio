--[[
	BreathBar.luau
	--------------
	UI Horror Safe Zone "Breath Meter" — Gaya Silencio Carnival Horror.

	Desain:
	  1. Font: `Enum.Font.Creepster` untuk headline status, `SpecialElite` untuk countdown.
	  2. Atmospheric Vignette: tepi layar menggelap dengan bayangan hitam/merah
	     darah yang bernapas dan semakin pekat saat napas kritis.
	  3. Bar Daging & Tulang: bingkai tebal gelap karat dengan gradien merah darah
	     pekat, dihiasi garis rusuk dan deretan 20 goresan kuku yang hangus per detik.
	  4. Jitter / Shaking: teks bergetar hebat saat panik (napas < 5s).
	  5. Anti-Nyangkut: jika state `COOLDOWN` atau `BREACHED` muncul dari penolakan,
	     UI otomatis pudar (fade out) dalam 1.8 detik jika tidak ada update baru.
	     State `NONE` / nil langsung menutup bar secara instan.
--]]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")

local BreathBar = {}
BreathBar.__index = BreathBar

local GUI_NAME = "SafeZoneBreath"
local MARKS    = 20

-- Warna tema darah karnaval
local COLOR_BLOOD_BRIGHT = Color3.fromRGB(190, 25, 30)
local COLOR_BLOOD_DARK   = Color3.fromRGB(50, 6, 8)
local COLOR_WARN_GOLD    = Color3.fromRGB(215, 140, 45)
local COLOR_RUST_BG      = Color3.fromRGB(15, 12, 14)
local COLOR_TEXT_LIGHT   = Color3.fromRGB(230, 215, 210)
local COLOR_TEXT_PANIC   = Color3.fromRGB(245, 45, 50)

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

	-- 1. Horror Vignette Overlay
	local vignette = new("ImageLabel", {
		Name = "HorrorVignette",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		BackgroundTransparency = 1,
		Image = "rbxassetid://6578550186", -- Texture vignette radial halus Roblox
		ImageColor3 = Color3.fromRGB(10, 0, 2),
		ImageTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(100, 100, 100, 100),
		Active = false,
		Parent = screen,
	})

	-- 2. HUD Container di bagian bawah layar
	local holder = new("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -65),
		Size = UDim2.new(0.32, 0, 0, 80),
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
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Font = Enum.Font.Creepster,
		TextSize = 26,
		TextColor3 = COLOR_TEXT_LIGHT,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		TextStrokeTransparency = 0,
		Text = "HOLDING BREATH",
		Active = false,
		Parent = holder,
	})

	-- 4. Countdown Angka (Font SpecialElite)
	local countdown = new("TextLabel", {
		Name = "Countdown",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -26),
		Size = UDim2.new(0, 50, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.SpecialElite,
		TextSize = 16,
		TextColor3 = COLOR_WARN_GOLD,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "20s",
		Active = false,
		Parent = holder,
	})

	-- 5. Deretan 20 Goresan Kuku (Scratches)
	local scratches = new("Frame", {
		Name = "Scratches",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 2, 1, -28),
		Size = UDim2.new(1, -56, 0, 12),
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
			Size = UDim2.new(0, 3, 0, (i % 2 == 0) and 10 or 7),
			BackgroundColor3 = Color3.fromRGB(160, 140, 130),
			BorderSizePixel = 0,
			Rotation = ((i * 7) % 15) - 7,
			LayoutOrder = i,
			Active = false,
			Parent = scratches,
		})
	end

	-- 6. Frame Bar Luar (Karat & Darah)
	local track = new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundColor3 = COLOR_RUST_BG,
		BorderSizePixel = 0,
		Active = false,
		Parent = holder,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 3), Parent = track })
	new("UIStroke", {
		Color = Color3.fromRGB(70, 10, 15),
		Thickness = 1.5,
		Transparency = 0.2,
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
	new("UICorner", { CornerRadius = UDim.new(0, 2), Parent = fill })

	local bloodGradient = new("UIGradient", {
		Color = ColorSequence.new(COLOR_BLOOD_BRIGHT, COLOR_BLOOD_DARK),
		Rotation = 90,
		Parent = fill,
	})

	-- 8. Garis Tulang Rusuk di atas Fill
	local ribs = new("Frame", {
		Name = "Ribs",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Active = false,
		Parent = track,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		Parent = ribs,
	})
	for i = 1, 28 do
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
	self.vignette = vignette
	self.holder = holder
	self.label = label
	self.countdown = countdown
	self.track = track
	self.fill = fill
	self.marks = marks
	self.bloodGradient = bloodGradient
	self.autoHideToken = 0
	self.pulseTween = nil

	return self
end

function BreathBar:_startVignettePulse(speed: number, maxAlpha: number)
	if self.pulseTween then
		self.pulseTween:Cancel()
		self.pulseTween = nil
	end

	self.vignette.ImageColor3 = Color3.fromRGB(40, 0, 5)
	self.pulseTween = TweenService:Create(
		self.vignette,
		TweenInfo.new(speed, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ ImageTransparency = maxAlpha }
	)
	self.pulseTween:Play()
end

function BreathBar:_stopVignette()
	if self.pulseTween then
		self.pulseTween:Cancel()
		self.pulseTween = nil
	end
	TweenService:Create(self.vignette, TweenInfo.new(0.4), { ImageTransparency = 1 }):Play()
end

function BreathBar:update(payload: { [string]: any }?)
	if not self.holder or not self.holder.Parent then
		return
	end

	-- State NONE / nil -> Hancurkan tampilan seketika (Anti-Nyangkut)
	if not payload or payload.state == nil or payload.state == "NONE" then
		self.autoHideToken += 1
		self:_stopVignette()
		TweenService:Create(self.holder, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 1, -40) }):Play()
		task.delay(0.25, function()
			if self.holder then
				self.holder.Visible = false
				self.holder.Position = UDim2.new(0.5, 0, 1, -65)
			end
		end)
		return
	end

	local state = tostring(payload.state)
	local fraction = math.clamp(tonumber(payload.fraction) or 0, 0, 1)
	local breathSec = math.max(0, math.floor((tonumber(payload.breath) or 0) + 0.5))

	-- Status teks & nuansa horor
	local labelText = TEXT[state] or state
	local labelColor = COLOR_TEXT_LIGHT

	if state == "OCCUPIED" then
		if fraction <= 0.25 then
			labelText = STRAIN.panic
			labelColor = COLOR_TEXT_PANIC
			self:_startVignettePulse(0.5, 0.25) -- Vignette merah darah berdenyut cepat
		elseif fraction <= 0.55 then
			labelText = STRAIN.warn
			labelColor = COLOR_WARN_GOLD
			self:_startVignettePulse(1.0, 0.55) -- Denyut pelan
		else
			labelText = TEXT.OCCUPIED
			labelColor = COLOR_TEXT_LIGHT
			self:_startVignettePulse(1.8, 0.75) -- Gelap samar di tepi
		end
		self.countdown.Text = string.format("%ds", breathSec)
		self.countdown.Visible = true
	else
		-- State BREACHED / COOLDOWN / FULL
		self.countdown.Visible = false
		labelColor = COLOR_TEXT_PANIC
		self:_stopVignette()

		-- AUTO-HIDE ANTI-NYANGKUT: Jika menerima status penolakan, tampilkan sebentar lalu hilang sendiri!
		self.autoHideToken += 1
		local currentToken = self.autoHideToken
		task.delay(1.8, function()
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
			mark.BackgroundColor3 = Color3.fromRGB(160, 140, 130)
			mark.BackgroundTransparency = 0.2
		else
			mark.BackgroundColor3 = Color3.fromRGB(35, 8, 12)
			mark.BackgroundTransparency = 0.8
		end
	end

	self.holder.Visible = true
end

function BreathBar:destroy()
	self:_stopVignette()
	if self.screen then
		self.screen:Destroy()
	end
	self.screen = nil
	self.holder = nil
	self.label = nil
	self.countdown = nil
	self.vignette = nil
	self.marks = nil
end

return BreathBar
