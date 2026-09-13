--[[
	BreathBar.luau
	--------------
	UI Horror Safe Zone "Breath Meter" — Silencio Carnival Horror.
	Tema: The Deflating Carnival Balloon (Balon Karnaval Mengempis).

	Visual:
	  1. Balon Merah Karnaval: Balon karet mewakili kapasitas udara paru-paru.
	     Semakin lama menahan napas, balon perlahan mengkerut dan mengempis.
	  2. Panic Tremble: Saat napas < 25% ("CAN'T HOLD ON!"), balon bergetar panik
	     menahan tekanan udara yang hampir habis.
	  3. POP Explosion (Meletus): Saat napas habis (0s / BREACHED), balon MELETUS
	     secara dramatis dengan serpihan karet terpental + shockwave merah,
	     menjadi transisi visual sebelum pemain terlempar keluar dari bilik!
	  4. Horror Vignette: 4-sisi bayangan darah pekat di sekeliling layar yang
	     berdenyut seiring ritme asfiksia.
	  5. Tipografi: `Enum.Font.SpecialElite` (vintage circus typewriter), bebas elemen kartun.
--]]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")

local BreathBar = {}
BreathBar.__index = BreathBar

local GUI_NAME = "SafeZoneBreath"

local COLOR_BALLOON_LIGHT = Color3.fromRGB(225, 40, 55)
local COLOR_BALLOON_DARK  = Color3.fromRGB(85, 8, 15)
local COLOR_TEXT_BONE     = Color3.fromRGB(225, 215, 210)
local COLOR_TEXT_WARN     = Color3.fromRGB(215, 100, 35)
local COLOR_TEXT_PANIC    = Color3.fromRGB(255, 45, 55)

local TEXT = {
	OCCUPIED = "HOLDING BREATH",
	BREACHED = "BURST!",
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

	-- 1. Horror Vignette: 4-sisi bayangan gelap/merah pekat di tepi layar
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
			NumberSequenceKeypoint.new(1, 1),
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
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = rightVig,
	})

	-- 2. HUD Container (responsive: auto-scale + batas ukuran pixel)
	local holder = new("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -70),
		Size = UDim2.new(0.35, 0, 0, 110),
		BackgroundTransparency = 1,
		Active = false,
		Visible = false,
		Parent = screen,
	})

	new("UISizeConstraint", {
		MinSize = Vector2.new(240, 90),
		MaxSize = Vector2.new(380, 120),
		Parent = holder,
	})

	-- 3. Wadah Balon Karnaval
	local balloonWrap = new("Frame", {
		Name = "BalloonWrap",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0, 60, 0, 64),
		BackgroundTransparency = 1,
		Active = false,
		Parent = holder,
	})

	-- Badan Balon
	local balloonBody = new("Frame", {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 0),
		Size = UDim2.new(0, 46, 0, 54),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Active = false,
		Parent = balloonWrap,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = balloonBody })

	local balloonGrad = new("UIGradient", {
		Color = ColorSequence.new(COLOR_BALLOON_LIGHT, COLOR_BALLOON_DARK),
		Rotation = 75,
		Parent = balloonBody,
	})

	-- Kilau Pantulan Cahaya (Specular Shine)
	local shine = new("Frame", {
		Name = "Shine",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0.2, 0, 0.18, 0),
		Size = UDim2.new(0, 10, 0, 6),
		BackgroundColor3 = Color3.fromRGB(255, 220, 230),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Rotation = -25,
		Parent = balloonBody,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = shine })

	-- Simpul Bawah Balon
	local knot = new("Frame", {
		Name = "Knot",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.new(0, 7, 0, 6),
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
		Position = UDim2.new(0.5, 0, 1, 3),
		Size = UDim2.new(0, 1, 0, 14),
		BackgroundColor3 = Color3.fromRGB(120, 100, 95),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Parent = balloonBody,
	})

	-- Serpihan Karet untuk Efek Meletus (POP!)
	local shreds = {}
	local shredContainer = new("Frame", {
		Name = "ShredContainer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 0),
		Size = UDim2.new(0, 50, 0, 50),
		BackgroundTransparency = 1,
		Active = false,
		Parent = balloonWrap,
	})

	for i = 1, 6 do
		local shred = new("Frame", {
			Name = "Shred" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 8, 0, 5),
			BackgroundColor3 = COLOR_BALLOON_LIGHT,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Rotation = i * 60,
			Parent = shredContainer,
		})
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = shred })
		table.insert(shreds, shred)
	end

	-- Shockwave Ring Merah saat Meletus
	local popRing = new("Frame", {
		Name = "PopRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 0),
		Size = UDim2.new(0, 10, 0, 10),
		BackgroundTransparency = 1,
		Parent = balloonWrap,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = popRing })
	local popStroke = new("UIStroke", {
		Color = COLOR_BALLOON_LIGHT,
		Thickness = 2,
		Transparency = 1,
		Parent = popRing,
	})

	-- 4. Label Status (SpecialElite)
	local label = new("TextLabel", {
		Name = "StatusLabel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.SpecialElite,
		TextSize = 14,
		TextColor3 = COLOR_TEXT_BONE,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.3,
		Text = "HOLDING BREATH",
		Active = false,
		Parent = holder,
	})

	-- 5. Hairline Sub-Gauge (Garis Tipis 3px)
	local gaugeTrack = new("Frame", {
		Name = "GaugeTrack",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0, 130, 0, 3),
		BackgroundColor3 = Color3.fromRGB(24, 16, 20),
		BorderSizePixel = 0,
		Active = false,
		Parent = holder,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = gaugeTrack })

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
				local ox = (math.random() - 0.5) * 4
				local oy = (math.random() - 0.5) * 3
				self.balloonBody.Position = UDim2.new(0.5, ox, 0.45, oy)
			end
			if self.label and self.label.Parent then
				local ox = (math.random() - 0.5) * 2
				self.label.Position = UDim2.new(0.5, ox, 1, -12)
			end
		end)
	elseif not enabled and self.jitterConn then
		self.jitterConn:Disconnect()
		self.jitterConn = nil
		if self.balloonBody then
			self.balloonBody.Position = UDim2.new(0.5, 0, 0.45, 0)
		end
		if self.label then
			self.label.Position = UDim2.new(0.5, 0, 1, -12)
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

	-- 1. Balon mengembang sekejap lalu hilang
	if self.balloonBody then
		self.balloonBody.Visible = false
	end

	if self.label then
		self.label.Text = "POP!"
		self.label.TextColor3 = COLOR_TEXT_PANIC
	end

	-- 2. Serpihan Karet Terpental Keluar (Explosion Scattering)
	local angles = { 0, 60, 120, 180, 240, 300 }
	for idx, shred in ipairs(self.shreds) do
		local rad = math.rad(angles[idx] or (idx * 60))
		local dist = math.random(26, 42)
		local tx = math.cos(rad) * dist
		local ty = math.sin(rad) * dist

		shred.Position = UDim2.new(0.5, 0, 0.5, 0)
		shred.BackgroundTransparency = 0
		shred.Visible = true

		TweenService:Create(shred, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, tx, 0.5, ty),
			BackgroundTransparency = 1,
			Rotation = shred.Rotation + math.random(90, 180)
		}):Play()
	end

	-- 3. Shockwave Ring Merah
	if self.popRing and self.popStroke then
		self.popRing.Size = UDim2.new(0, 8, 0, 8)
		self.popStroke.Transparency = 0
		TweenService:Create(self.popRing, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 56, 0, 56)
		}):Play()
		TweenService:Create(self.popStroke, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1
		}):Play()
	end

	-- Flash Vignette Merah Pekat
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
		TweenService:Create(self.holder, TweenInfo.new(0.2), { Position = UDim2.new(0.5, 0, 1, -40) }):Play()
		task.delay(0.2, function()
			if self.holder then
				self.holder.Visible = false
				self.holder.Position = UDim2.new(0.5, 0, 1, -70)
				self.popped = false
				if self.balloonBody then
					self.balloonBody.Visible = true
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
			-- Napas habis -> meletus seketika!
			self:popBalloon()
			return
		elseif fraction <= 0.25 then
			labelText = STRAIN.panic
			labelColor = COLOR_TEXT_PANIC
			self:_startVignettePulse(0.35, 0.2) -- Denyut merah cepat saat napas kritis
			self:_setJitter(true)              -- Balon & teks bergetar panik
		elseif fraction <= 0.55 then
			labelText = STRAIN.warn
			labelColor = COLOR_TEXT_WARN
			self:_startVignettePulse(0.8, 0.45) -- Denyut sedang
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
		end
	elseif state == "BREACHED" then
		-- Bilik jebol / napas habis -> Meletus!
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
		-- State COOLDOWN / FULL
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

	-- Ukuran Balon Mengempis (Deflating) mengikuti sisa napas
	-- Dari 46x54 px (saat 1.0) turun ke 20x24 px (saat hampir habis)
	if not self.popped and self.balloonBody then
		local curW = math.floor(20 + fraction * 26)
		local curH = math.floor(24 + fraction * 30)
		TweenService:Create(
			self.balloonBody,
			TweenInfo.new(0.12, Enum.EasingStyle.Linear),
			{ Size = UDim2.new(0, curW, 0, curH) }
		):Play()
	end

	-- Tween Garis Sub-Gauge
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
