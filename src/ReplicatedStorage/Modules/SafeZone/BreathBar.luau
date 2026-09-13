--[[
	BreathBar.luau
	--------------
	UI Horror Safe Zone "Breath Meter" — Silencio Carnival Horror.
	Tema: The Deflating Carnival Balloon (Balon Karnaval Mengempis) V2 - High Impact.

	Fitur:
	  1. Skala Besar & Dramatis: Balon berukuran besar (74x88 px saat penuh),
	     dengan pencahayaan specular gloss, bayangan karet tebal, simpul, dan benang.
	  2. Mengempis Proporsional: Volume balon menyusut dinamis dari 74x88 px
	     turun ke 34x42 px saat napas menipis.
	  3. Panic Tremble: Saat napas < 25%, balon dan teks bergetar panik
	     menahan tekanan dada yang tersedak.
	  4. POP Explosion (Meletus): Saat napas habis (0s / BREACHED), balon MELETUS
	     dramatis dengan 8 serpihan karet terpental + shockwave merah 100px!
	  5. Tipografi Bersih: `SpecialElite` ukuran 20px berjarak, teks stroke kontras,
	     sub-gauge 220px dengan frame outline merah darah.
--]]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")

local BreathBar = {}
BreathBar.__index = BreathBar

local GUI_NAME = "SafeZoneBreath"

local COLOR_BALLOON_LIGHT = Color3.fromRGB(235, 45, 60)
local COLOR_BALLOON_DARK  = Color3.fromRGB(70, 6, 12)
local COLOR_TEXT_BONE     = Color3.fromRGB(235, 225, 220)
local COLOR_TEXT_WARN     = Color3.fromRGB(225, 110, 40)
local COLOR_TEXT_PANIC    = Color3.fromRGB(255, 45, 60)

local TEXT = {
	OCCUPIED = "HOLDING BREATH",
	BREACHED = "POP!",
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
	local playerGui = player and (player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5))
	if not playerGui then
		playerGui = Instance.new("Folder")
	end

	local screen = playerGui:FindFirstChild(GUI_NAME) or new("ScreenGui", {
		Name = GUI_NAME,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 15,
		Parent = playerGui,
	})
	pcall(function()
		screen.ScreenInsets = Enum.ScreenInsets.None
		screen.ClipToDeviceSafeArea = false
	end)
	screen:ClearAllChildren()

	-- 1. Horror Vignette Full Screen (Edge-to-Edge)
	local vignetteContainer = new("Frame", {
		Name = "HorrorVignette",
		Position = UDim2.fromScale(0, 0),
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
			NumberSequenceKeypoint.new(1, 1),
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
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = bottomVig,
	})

	local leftVig = new("Frame", {
		Size = UDim2.new(0.35, 0, 1, 0),
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
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = leftVig,
	})

	local rightVig = new("Frame", {
		Size = UDim2.new(0.35, 0, 1, 0),
		Position = UDim2.new(0.65, 0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(20, 0, 3),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = vignetteContainer,
	})
	new("UIGradient", {
		Rotation = 180,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = rightVig,
	})

	-- 2. HUD Container (Proporsi Lebih Besar & Mewah)
	local holder = new("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -65),
		Size = UDim2.new(0.4, 0, 0, 155),
		BackgroundTransparency = 1,
		Active = false,
		Visible = false,
		Parent = screen,
	})

	new("UISizeConstraint", {
		MinSize = Vector2.new(300, 140),
		MaxSize = Vector2.new(480, 175),
		Parent = holder,
	})

	-- 3. Wadah Balon Karnaval
	local balloonWrap = new("Frame", {
		Name = "BalloonWrap",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0, 110, 0, 115),
		BackgroundTransparency = 1,
		Active = false,
		Parent = holder,
	})

	-- Aura Cahaya Merah Lembut di Belakang Balon
	local balloonAura = new("Frame", {
		Name = "Aura",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0, 95, 0, 110),
		BackgroundColor3 = Color3.fromRGB(180, 20, 35),
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Active = false,
		Parent = balloonWrap,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = balloonAura })

	-- Badan Balon (Oval Karnaval)
	local balloonBody = new("Frame", {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0, 74, 0, 88),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Active = false,
		Parent = balloonWrap,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = balloonBody })

	local balloonGrad = new("UIGradient", {
		Color = ColorSequence.new(COLOR_BALLOON_LIGHT, COLOR_BALLOON_DARK),
		Rotation = 72,
		Parent = balloonBody,
	})

	new("UIStroke", {
		Color = Color3.fromRGB(110, 12, 22),
		Thickness = 1.5,
		Transparency = 0.25,
		Parent = balloonBody,
	})

	-- Kilau Pantulan Cahaya (Specular Gloss Highlight)
	local shine = new("Frame", {
		Name = "Shine",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0.18, 0, 0.15, 0),
		Size = UDim2.new(0, 16, 0, 10),
		BackgroundColor3 = Color3.fromRGB(255, 235, 240),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Rotation = -28,
		Parent = balloonBody,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = shine })

	-- Simpul Bawah Balon
	local knot = new("Frame", {
		Name = "Knot",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(0, 11, 0, 9),
		BackgroundColor3 = COLOR_BALLOON_DARK,
		BorderSizePixel = 0,
		Rotation = 45,
		Parent = balloonBody,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 2), Parent = knot })

	-- Tali Benang Balon
	local stringLine = new("Frame", {
		Name = "String",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 5),
		Size = UDim2.new(0, 1.5, 0, 22),
		BackgroundColor3 = Color3.fromRGB(140, 115, 110),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = balloonBody,
	})

	-- 8 Serpihan Karet untuk Efek Meletus (POP!)
	local shreds = {}
	local shredContainer = new("Frame", {
		Name = "ShredContainer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0, 80, 0, 80),
		BackgroundTransparency = 1,
		Active = false,
		Parent = balloonWrap,
	})

	for i = 1, 8 do
		local shred = new("Frame", {
			Name = "Shred" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 12, 0, 7),
			BackgroundColor3 = COLOR_BALLOON_LIGHT,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Rotation = i * 45,
			Parent = shredContainer,
		})
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = shred })
		table.insert(shreds, shred)
	end

	-- Shockwave Ring Merah saat Meletus
	local popRing = new("Frame", {
		Name = "PopRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0, 12, 0, 12),
		BackgroundTransparency = 1,
		Parent = balloonWrap,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = popRing })
	local popStroke = new("UIStroke", {
		Color = COLOR_BALLOON_LIGHT,
		Thickness = 2.5,
		Transparency = 1,
		Parent = popRing,
	})

	-- 4. Label Status Utama (Besar & Jelas)
	local label = new("TextLabel", {
		Name = "StatusLabel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		Font = Enum.Font.SpecialElite,
		TextSize = 18,
		TextColor3 = COLOR_TEXT_BONE,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0,
		Text = "HOLDING BREATH",
		Active = false,
		Parent = holder,
	})

	-- 5. Sub-Gauge Hairline Tipis Elegan (220px x 4px)
	local gaugeTrack = new("Frame", {
		Name = "GaugeTrack",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0, 220, 0, 4),
		BackgroundColor3 = Color3.fromRGB(26, 16, 20),
		BorderSizePixel = 0,
		Active = false,
		Parent = holder,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = gaugeTrack })
	new("UIStroke", {
		Color = Color3.fromRGB(80, 15, 24),
		Thickness = 1,
		Transparency = 0.3,
		Parent = gaugeTrack,
	})

	local gaugeFill = new("Frame", {
		Name = "GaugeFill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLOR_BALLOON_LIGHT,
		BorderSizePixel = 0,
		Active = false,
		Parent = gaugeTrack,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = gaugeFill })

	self.screen = screen
	self.vignetteContainer = vignetteContainer
	self.vigFrames = { topVig, bottomVig, leftVig, rightVig }
	self.holder = holder
	self.balloonWrap = balloonWrap
	self.balloonAura = balloonAura
	self.balloonBody = balloonBody
	self.balloonGrad = balloonGrad
	self.knot = knot
	self.stringLine = stringLine
	self.shreds = shreds
	self.popRing = popRing
	self.popStroke = popStroke
	self.label = label
	self.gaugeTrack = gaugeTrack
	self.gaugeFill = gaugeFill
	self.autoHideToken = 0
	self.pulseTween = nil
	self.jitterConn = nil
	self.popped = false

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
			if self.balloonBody and self.balloonBody.Parent then
				local ox = (math.random() - 0.5) * 5
				local oy = (math.random() - 0.5) * 4
				self.balloonBody.Position = UDim2.new(0.5, ox, 0.42, oy)
			end
			if self.balloonAura and self.balloonAura.Parent then
				local ox = (math.random() - 0.5) * 6
				local oy = (math.random() - 0.5) * 5
				self.balloonAura.Position = UDim2.new(0.5, ox, 0.42, oy)
			end
			if self.label and self.label.Parent then
				local ox = (math.random() - 0.5) * 3
				self.label.Position = UDim2.new(0.5, ox, 1, -16)
			end
		end)
	elseif not enabled and self.jitterConn then
		self.jitterConn:Disconnect()
		self.jitterConn = nil
		if self.balloonBody then
			self.balloonBody.Position = UDim2.new(0.5, 0, 0.42, 0)
		end
		if self.balloonAura then
			self.balloonAura.Position = UDim2.new(0.5, 0, 0.42, 0)
		end
		if self.label then
			self.label.Position = UDim2.new(0.5, 0, 1, -16)
		end
	end
end

--- Efek Meletus (POP!) saat napas habis / pemain diusir paksa
function BreathBar:popBalloon()
	if self.popped then
		return
	end
	self.popped = true
	self:_setJitter(false)

	-- 1. Sembunyikan balon dan aura
	if self.balloonBody then
		self.balloonBody.Visible = false
	end
	if self.balloonAura then
		self.balloonAura.Visible = false
	end

	if self.label then
		self.label.Text = "POP!"
		self.label.TextSize = 24
		self.label.TextColor3 = COLOR_TEXT_PANIC
	end

	-- 2. 8 Serpihan Karet Terpental Keluar Melingkar
	local angles = { 0, 45, 90, 135, 180, 225, 270, 315 }
	for idx, shred in ipairs(self.shreds) do
		local rad = math.rad(angles[idx] or (idx * 45))
		local dist = math.random(35, 55)
		local tx = math.cos(rad) * dist
		local ty = math.sin(rad) * dist

		shred.Position = UDim2.new(0.5, 0, 0.5, 0)
		shred.BackgroundTransparency = 0
		shred.Visible = true

		TweenService:Create(shred, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, tx, 0.5, ty),
			BackgroundTransparency = 1,
			Rotation = shred.Rotation + math.random(120, 240)
		}):Play()
	end

	-- 3. Shockwave Ring Merah 90px
	if self.popRing and self.popStroke then
		self.popRing.Size = UDim2.new(0, 12, 0, 12)
		self.popStroke.Transparency = 0
		TweenService:Create(self.popRing, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 90, 0, 90)
		}):Play()
		TweenService:Create(self.popStroke, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1
		}):Play()
	end

	-- Flash Vignette Darah
	self:_setVignetteAlpha(0.1, 0.08)
	task.delay(0.1, function()
		self:_setVignetteAlpha(1, 0.4)
	end)
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
		TweenService:Create(self.holder, TweenInfo.new(0.2), { Position = UDim2.new(0.5, 0, 1, -35) }):Play()
		task.delay(0.2, function()
			if self.holder then
				self.holder.Visible = false
				self.holder.Position = UDim2.new(0.5, 0, 1, -65)
				self.popped = false
				if self.balloonBody then
					self.balloonBody.Visible = true
				end
				if self.balloonAura then
					self.balloonAura.Visible = true
				end
				if self.label then
					self.label.TextSize = 18
				end
			end
		end)
		return
	end

	local state = tostring(payload.state)
	local fraction = math.clamp(tonumber(payload.fraction) or 0, 0, 1)

	local labelText = TEXT[state] or state
	local labelColor = COLOR_TEXT_BONE

	if state == "OCCUPIED" then
		if fraction <= 0 then
			self:popBalloon()
			return
		elseif fraction <= 0.25 then
			labelText = STRAIN.panic
			labelColor = COLOR_TEXT_PANIC
			self:_startVignettePulse(0.35, 0.2)
			self:_setJitter(true)
		elseif fraction <= 0.55 then
			labelText = STRAIN.warn
			labelColor = COLOR_TEXT_WARN
			self:_startVignettePulse(0.8, 0.45)
			self:_setJitter(false)
		else
			labelText = TEXT.OCCUPIED
			labelColor = COLOR_TEXT_BONE
			self:_setVignetteAlpha(0.65, 0.5)
			self:_setJitter(false)
		end

		-- Reset popped state jika pemain baru masuk
		if self.popped and fraction > 0.1 then
			self.popped = false
			if self.balloonBody then
				self.balloonBody.Visible = true
			end
			if self.balloonAura then
				self.balloonAura.Visible = true
			end
			if self.label then
				self.label.TextSize = 18
			end
		end
	elseif state == "BREACHED" then
		self:popBalloon()
		labelColor = COLOR_TEXT_PANIC

		self.autoHideToken += 1
		local currentToken = self.autoHideToken
		task.delay(1.5, function()
			if self.autoHideToken == currentToken and self.holder then
				self:update(nil)
			end
		end)
		return
	else
		labelColor = COLOR_TEXT_PANIC
		self:_stopVignette()
		self:_setJitter(false)

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

	-- Ukuran Balon Mengempis Proporsional (Besar & Mantap):
	-- Dari 74x88 px (saat 1.0) turun ke 34x42 px (saat hampir habis)
	if not self.popped and self.balloonBody then
		local curW = math.floor(34 + fraction * 40)
		local curH = math.floor(42 + fraction * 46)
		TweenService:Create(
			self.balloonBody,
			TweenInfo.new(0.12, Enum.EasingStyle.Linear),
			{ Size = UDim2.new(0, curW, 0, curH) }
		):Play()

		if self.balloonAura then
			local auraW = curW + 18
			local auraH = curH + 18
			TweenService:Create(
				self.balloonAura,
				TweenInfo.new(0.12, Enum.EasingStyle.Linear),
				{ Size = UDim2.new(0, auraW, 0, auraH) }
			):Play()
		end
	end

	-- Tween Sub-Gauge
	TweenService:Create(
		self.gaugeFill,
		TweenInfo.new(0.12, Enum.EasingStyle.Linear),
		{ Size = UDim2.fromScale(fraction, 1) }
	):Play()

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
	self.balloonWrap = nil
	self.balloonAura = nil
	self.balloonBody = nil
	self.shreds = nil
	self.popRing = nil
	self.popStroke = nil
	self.label = nil
	self.gaugeTrack = nil
	self.gaugeFill = nil
	self.vignetteContainer = nil
	self.vigFrames = nil
end

return BreathBar
